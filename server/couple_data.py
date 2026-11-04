"""Authenticated shared couple data. Separate collections; no client DB access."""
import base64
import hashlib
import json
import math
import os
import secrets
import time
import requests
import cachecontrol
from datetime import datetime, timezone
from google.cloud import firestore, storage
from google.oauth2 import id_token
from google.auth.transport.requests import Request as GoogleRequest
from demo_security import AccessError

_CERT_REQUEST = GoogleRequest(session=cachecontrol.CacheControl(requests.Session()))


def clean(value, limit, required=True):
    if not isinstance(value, str) or len(value) > limit or (required and not value.strip()):
        raise AccessError(400, 'Check the fields and try again.')
    return value.strip()


class CoupleData:
    def __init__(self):
        self.project = os.environ['GOOGLE_CLOUD_PROJECT']
        self.db = firestore.Client(project=self.project, database=os.environ.get('FIRESTORE_DATABASE', 'closer-demo-backend'))
        self.bucket = storage.Client(project=self.project).bucket(os.environ.get('CLOSER_MEDIA_BUCKET', self.project + '-closer-media'))

    def user(self, token):
        if isinstance(token, str) and token.startswith('room_'):
            session = self.db.collection('court_room_sessions').document(hashlib.sha256(token.encode()).hexdigest()).get().to_dict()
            if not session or session['expires'] <= time.time():
                raise AccessError(401, 'Your room session expired. Create a new room or use your existing browser session.')
            return session['uid']
        try:
            claims = id_token.verify_firebase_token(token, _CERT_REQUEST, audience=self.project)
            uid = claims['sub']
            if not uid or len(uid) > 128:
                raise ValueError()
            return uid
        except Exception:
            raise AccessError(401, 'Please sign in again.')

    def room_admit(self, client):
        # Anonymous room creation/joining is bounded independently of AI budgets.
        now = int(time.time())
        refs = [(self.db.collection('court_room_limits').document('global'), 200),
                (self.db.collection('court_room_limits').document(hashlib.sha256(client.encode()).hexdigest()), 12)]
        @firestore.transactional
        def reserve(tx):
            records = [ref.get(transaction=tx).to_dict() or {} for ref, _ in refs]
            for record, (_, limit) in zip(records, refs):
                if record.get('day') == now // 86400 and record.get('count', 0) >= limit:
                    raise AccessError(429, 'The room creation/join allowance has been reached. Try again tomorrow.')
            for record, (ref, _) in zip(records, refs):
                count = record.get('count', 0) if record.get('day') == now // 86400 else 0
                tx.set(ref, {'day': now // 86400, 'count': count + 1})
        reserve(self.db.transaction())

    @staticmethod
    def room_fields(body):
        if not isinstance(body, dict):
            raise AccessError(400, 'Enter your name and upload a selfie.')
        name = clean(body.get('name'), 50)
        if body.get('consent') is not True:
            raise AccessError(400, 'Confirm you have permission to share this selfie.')
        image = body.get('image_base64')
        if not isinstance(image, str) or len(image) > 1400000:
            raise AccessError(400, 'Use a JPEG or PNG selfie smaller than 1 MB.')
        try:
            raw = base64.b64decode(image, validate=True)
        except Exception:
            raise AccessError(400, 'Invalid selfie.')
        if not raw or len(raw) > 1000000 or not (raw.startswith(b'\xff\xd8\xff') or raw.startswith(b'\x89PNG\r\n\x1a\n')):
            raise AccessError(400, 'Use a JPEG or PNG selfie smaller than 1 MB.')
        return name, raw

    def room_enter(self, body, joining=False):
        name, raw = self.room_fields(body)
        token = 'room_' + secrets.token_urlsafe(32)
        session_ref = self.db.collection('court_room_sessions').document(hashlib.sha256(token.encode()).hexdigest())
        photo_id = secrets.token_hex(16)
        now = time.time()
        if joining:
            code = clean(body.get('code'), 100)
            invite_ref = self.db.collection('court_room_invites').document(hashlib.sha256(code.encode()).hexdigest())
            invite = invite_ref.get().to_dict()
            if not invite or invite.get('used') or invite['expires'] <= now:
                raise AccessError(409, 'This room invitation has expired or its second seat is already taken.')
            cid, uid = invite['roomId'], invite['guestId']
            root = self.db.collection('closer_couples').document(cid)
            # Upload only after validating the invitation; a losing concurrent join cleans up its blob.
            blob = self.bucket.blob(f'{cid}/{photo_id}')
            blob.upload_from_string(raw, content_type='image/jpeg' if raw.startswith(b'\xff') else 'image/png')
            try:
                @firestore.transactional
                def join(tx):
                    current = invite_ref.get(transaction=tx).to_dict()
                    room = root.get(transaction=tx).to_dict()
                    hearing_ref = root.collection('hearings').document('hearing')
                    hearing = hearing_ref.get(transaction=tx).to_dict()
                    if not current or current.get('used') or current['expires'] <= time.time() or not room or room.get('expires', 0) <= time.time():
                        raise AccessError(409, 'This invitation is no longer available.')
                    hearing['names'][1] = name
                    hearing['portraits'][1] = photo_id
                    hearing['version'] += 1
                    tx.update(root, {f'names.{uid}': name, f'portraits.{uid}': photo_id, 'guestJoined': True})
                    tx.set(self.db.collection('closer_profiles').document(uid), {'name': name, 'coupleId': cid})
                    tx.set(root.collection('photos').document(photo_id), {'owner': uid})
                    tx.set(hearing_ref, hearing)
                    tx.update(invite_ref, {'used': True})
                    tx.set(session_ref, {'uid': uid, 'expires': room['expires']})
                    return room['expires']
                expiry = join(self.db.transaction())
            except Exception:
                blob.delete()
                raise
            return {'session': token, 'uid': uid, 'roomId': cid, 'caseId': 'hearing', 'expires': expiry}
        topic = clean(body.get('topic'), 1000)
        root = self.db.collection('closer_couples').document()
        cid = root.id
        uid, guest = 'room_' + secrets.token_hex(16), 'room_' + secrets.token_hex(16)
        code = secrets.token_urlsafe(24)
        expiry = now + 7 * 86400
        room = {'members': [uid, guest], 'names': {uid: name, guest: 'Your partner'},
                'portraits': {uid: photo_id}, 'createdAt': datetime.now(timezone.utc).isoformat(),
                'locations': {}, 'roomOnly': True, 'expires': expiry, 'guestJoined': False}
        message = {'kind': 'court', 'text': topic, 'senderId': uid, 'status': 'open', 'createdAt': room['createdAt'], 'hearts': []}
        from shared_court import initial
        hearing = initial(room, message)
        hearing['portraits'] = [photo_id, None]
        self.bucket.blob(f'{cid}/{photo_id}').upload_from_string(raw, content_type='image/jpeg' if raw.startswith(b'\xff') else 'image/png')
        batch = self.db.batch()
        batch.set(root, room)
        batch.set(self.db.collection('closer_profiles').document(uid), {'name': name, 'coupleId': cid})
        batch.set(root.collection('photos').document(photo_id), {'owner': uid})
        batch.set(root.collection('messages').document('hearing'), message)
        batch.set(root.collection('hearings').document('hearing'), hearing)
        batch.set(session_ref, {'uid': uid, 'expires': expiry})
        batch.set(self.db.collection('court_room_invites').document(hashlib.sha256(code.encode()).hexdigest()),
                  {'roomId': cid, 'guestId': guest, 'expires': now + 86400, 'used': False})
        batch.commit()
        return {'session': token, 'uid': uid, 'roomId': cid, 'caseId': 'hearing', 'invite': code, 'expires': expiry}

    def admit(self, uid, photo=False, memory_tag=False):
        ref = self.db.collection('closer_app_limits').document(uid)
        now = int(time.time())
        @firestore.transactional
        def reserve(tx):
            record = ref.get(transaction=tx).to_dict() or {}
            minute, day = now // 60, now // 86400
            calls = record.get('calls', 0) if record.get('minute') == minute else 0
            photos = record.get('photos', 0) if record.get('day') == day else 0
            tags = record.get('memoryTags', 0) if record.get('day') == day else 0
            if calls >= 90 or (photo and photos >= 20) or (memory_tag and tags >= 20):
                raise AccessError(429, 'Please wait before uploading or syncing again.')
            tx.set(ref, {'minute': minute, 'calls': calls+1, 'day': day,
                         'photos': photos + int(photo), 'memoryTags': tags + int(memory_tag)})
        reserve(self.db.transaction())

    def member(self, uid):
        profile = self.db.collection('closer_profiles').document(uid).get().to_dict() or {}
        cid = profile.get('coupleId')
        if not cid:
            raise AccessError(409, 'Pair with your partner first.')
        couple = self.db.collection('closer_couples').document(cid).get().to_dict()
        if not couple or uid not in couple['members']:
            raise AccessError(403, 'This shared space is unavailable.')
        if couple.get('roomOnly') and couple.get('expires', 0) <= time.time():
            raise AccessError(410, 'This court room has expired.')
        return cid, couple

    def state(self, uid):
        profile = self.db.collection('closer_profiles').document(uid).get().to_dict() or {}
        if not profile.get('coupleId'):
            return {'profile': profile, 'couple': None, 'messages': [], 'memories': []}
        cid, couple = self.member(uid)
        root = self.db.collection('closer_couples').document(cid)
        def records(collection):
            docs = root.collection(collection).order_by('createdAt', direction=firestore.Query.DESCENDING).limit(150).stream()
            return [{'id': doc.id, **doc.to_dict()} for doc in docs]
        avatars = {}
        statuses = {}
        for member_id in couple.get('members', []):
            member_profile = self.db.collection('closer_profiles').document(member_id).get().to_dict() or {}
            status = member_profile.get('deviceStatus', {})
            if status.get('coupleId') == cid:
                statuses[member_id] = status
            if member_profile.get('avatarPhotoId'):
                avatars[member_id] = member_profile['avatarPhotoId']
        return {'profile': profile, 'couple': {'id': cid, **couple, 'avatars': avatars, 'deviceStatuses': statuses},
                'messages': list(reversed(records('messages'))), 'memories': records('memories')}

    @staticmethod
    def _meters_between(lat1, lon1, lat2, lon2):
        radius = 6371000
        phi1, phi2 = math.radians(lat1), math.radians(lat2)
        dphi, dlambda = math.radians(lat2-lat1), math.radians(lon2-lon1)
        value = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
        return radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1-value))

    def _send_place_alerts(self, receiver, events):
        """Send best-effort FCM alerts after a partner crosses a saved geofence."""
        try:
            import firebase_admin
            from firebase_admin import messaging
            try:
                app = firebase_admin.get_app()
            except ValueError:
                app = firebase_admin.initialize_app(options={'projectId': self.project})
            profile_ref = self.db.collection('closer_profiles').document(receiver)
            fids = (profile_ref.get().to_dict() or {}).get('pushIds', [])
            fids = [fid for fid in fids if isinstance(fid, str) and fid]
            if not fids:
                return
            for event in events:
                for start in range(0, len(fids), 500):
                    batch = fids[start:start+500]
                    message = messaging.MulticastMessage(
                        fids=batch,
                        notification=messaging.Notification(
                            title=event.get('title', 'Closer · Place alert'),
                            body=event['text'],
                        ),
                        data={'type': event.get('type', 'saved_place'), 'placeId': event.get('placeId', ''), 'messageId': event.get('messageId', ''), 'sentAt': event.get('sentAt', '')},
                        android=messaging.AndroidConfig(
                            priority='high',
                            notification=messaging.AndroidNotification(
                                channel_id='closer_chat_messages' if event.get('type') in {'chat', 'metherapy_invite'} else 'closer_place_alerts',
                                event_timestamp=datetime.fromisoformat(event['sentAt'].replace('Z', '+00:00')) if event.get('sentAt') else None,
                                tag=event.get('messageId') or None, sound='default'),
                        ),
                        apns=messaging.APNSConfig(
                            payload=messaging.APNSPayload(aps=messaging.Aps(sound='default')),
                        ),
                    )
                    messaging.send_each_for_multicast(message, app=app)
        except Exception as error:
            # The location write remains successful if push delivery is unavailable.
            print(f'Saved-place push delivery failed: {type(error).__name__}')

    def action(self, uid, body):
        if not isinstance(body, dict):
            raise AccessError(400, 'Invalid request.')
        action = body.get('action')
        if uid.startswith('room_') and (action != 'message' or body.get('summons')):
            raise AccessError(403, 'This session is for your court room only.')
        profile_ref = self.db.collection('closer_profiles').document(uid)
        now = datetime.now(timezone.utc).isoformat()
        if action == 'profile':
            name = clean(body.get('name'), 50)
            update = {'name': name}
            if body.get('avatarPhotoId') is not None:
                avatar_id = clean(body.get('avatarPhotoId'), 32)
                if not re_photo(avatar_id):
                    raise AccessError(400, 'Invalid profile photo.')
                photo_ref = self.db.collection('closer_couples').document(self.member(uid)[0]).collection('photos').document(avatar_id)
                photo = photo_ref.get().to_dict() or {}
                if photo.get('owner') != uid:
                    raise AccessError(403, 'You can only use a photo you uploaded.')
                update['avatarPhotoId'] = avatar_id
            profile_ref.set(update, merge=True)
            profile = profile_ref.get().to_dict()
            if profile.get('coupleId'):
                cid, _ = self.member(uid)
                self.db.collection('closer_couples').document(cid).update({f'names.{uid}': name})
        elif action == 'invite':
            profile = profile_ref.get().to_dict() or {}
            if profile.get('coupleId'):
                raise AccessError(409, 'You are already paired.')
            if not profile.get('name'):
                raise AccessError(400, 'Set your name first.')
            code = secrets.token_urlsafe(18)
            key = hashlib.sha256(code.encode()).hexdigest()
            self.db.collection('closer_pair_invites').document(key).set({'owner': uid, 'expires': time.time()+86400})
            return {'code': code}
        elif action == 'join':
            code = clean(body.get('code'), 100)
            invite_ref = self.db.collection('closer_pair_invites').document(hashlib.sha256(code.encode()).hexdigest())
            couple_ref = self.db.collection('closer_couples').document()
            @firestore.transactional
            def pair(tx):
                invite = invite_ref.get(transaction=tx).to_dict()
                if not invite or invite.get('used') or invite['expires'] < time.time() or invite['owner'] == uid:
                    raise AccessError(400, 'That invitation is expired or unavailable.')
                owner = invite['owner']
                owner_ref = self.db.collection('closer_profiles').document(owner)
                profiles = [profile_ref.get(transaction=tx).to_dict() or {}, owner_ref.get(transaction=tx).to_dict() or {}]
                if any(p.get('coupleId') for p in profiles) or any(not p.get('name') for p in profiles):
                    raise AccessError(409, 'Both people need a name and must not already be paired.')
                tx.set(couple_ref, {'members': [owner, uid], 'names': {owner: profiles[1]['name'], uid: profiles[0]['name']}, 'createdAt': now, 'locations': {}, 'therapyLanguage': 'en'})
                tx.update(profile_ref, {'coupleId': couple_ref.id})
                tx.update(owner_ref, {'coupleId': couple_ref.id})
                tx.update(invite_ref, {'used': True})
            pair(self.db.transaction())
        elif action == 'therapy_language':
            language = clean(body.get('language'), 8)
            if language not in {'en', 'id', 'ms', 'hi', 'fil'}:
                raise AccessError(400, 'Choose a supported Metherapy language.')
            cid, _ = self.member(uid)
            self.db.collection('closer_couples').document(cid).update({'therapyLanguage': language, 'therapyLanguageUpdatedAt': now})
        elif action == 'unpair':
            @firestore.transactional
            def detach(tx):
                current_profile = profile_ref.get(transaction=tx).to_dict() or {}
                cid = current_profile.get('coupleId')
                if not cid:
                    return False
                couple_ref = self.db.collection('closer_couples').document(cid)
                current_couple = couple_ref.get(transaction=tx).to_dict() or {}
                members = current_couple.get('members', [])
                if uid not in members:
                    tx.update(profile_ref, {'coupleId': firestore.DELETE_FIELD, 'avatarPhotoId': firestore.DELETE_FIELD})
                    return True
                refs = [self.db.collection('closer_profiles').document(member) for member in members]
                snapshots = [ref.get(transaction=tx).to_dict() or {} for ref in refs]
                for ref, snapshot in zip(refs, snapshots):
                    if snapshot.get('coupleId') == cid:
                        tx.update(ref, {'coupleId': firestore.DELETE_FIELD, 'avatarPhotoId': firestore.DELETE_FIELD})
                tx.update(couple_ref, {'members': [], 'locations': {}, 'savedPlaces': [], 'unpairedAt': now})
                return True
            return {'unpaired': detach(self.db.transaction())}
        else:
            cid, couple = self.member(uid)
            root = self.db.collection('closer_couples').document(cid)
            if action == 'device_status':
                battery = body.get('battery')
                if battery is not None and (type(battery) is not int or not 0 <= battery <= 100):
                    raise AccessError(400, 'Invalid battery level.')
                if type(body.get('charging')) is not bool or body.get('connection') not in {'wifi', 'mobile', 'offline', 'other'}:
                    raise AccessError(400, 'Invalid device status.')
                self.db.collection('closer_profiles').document(uid).set({'deviceStatus': {
                    'battery': battery, 'charging': body['charging'], 'connection': body['connection'],
                    'coupleId': cid, 'updatedAt': datetime.now(timezone.utc).isoformat()}}, merge=True)
                return {'ok': True}
            if action == 'memory_capabilities':
                return {'albums': True, 'deleteMemories': True}
            if action in {'message', 'memory'}:
                item_id = clean(body.get('id'), 80)
                if not all(c.isalnum() or c in '_-' for c in item_id):
                    raise AccessError(400, 'Invalid record.')
                text = clean(body.get('text', ''), 2000, False)
                photo = body.get('photoId')
                if photo:
                    photo = clean(photo, 80)
                    meta = root.collection('photos').document(photo).get().to_dict()
                    if not meta or meta['owner'] != uid:
                        raise AccessError(403, 'Photo unavailable.')
                if not text and not photo:
                    raise AccessError(400, 'Add a message or photo.')
                collection = 'memories' if action == 'memory' else 'messages'
                ref = root.collection(collection).document(item_id)
                if ref.get().exists:
                    return self.state(uid)
                item = {'text': text, 'createdAt': now, 'senderId': uid, 'photoId': photo,
                        'kind': 'photo' if photo else 'text', 'hearts': []}
                if action == 'memory':
                    album = clean(body.get('album', ''), 80, False)
                    memory_date = clean(body.get('memoryDate', now), 40)
                    try:
                        datetime.fromisoformat(memory_date.replace('Z', '+00:00'))
                    except ValueError:
                        raise AccessError(400, 'Choose a valid memory date.')
                    tags = body.get('tags', [])
                    if not isinstance(tags, list) or len(tags) > 12 or any(not isinstance(tag, str) or len(tag) > 32 for tag in tags):
                        raise AccessError(400, 'Memory tags are invalid.')
                    item.update(album=album, memoryDate=memory_date, tags=[tag.strip().lower() for tag in tags if tag.strip()])
                if action == 'message' and body.get('summons') is True:
                    language = body.get('therapyLanguage', 'en')
                    if language not in {'en', 'id', 'ms', 'hi', 'fil'}:
                        raise AccessError(400, 'Choose a supported Metherapy language.')
                    item.update(kind='court', status='open', therapyLanguage=language)
                reply_id = body.get('replyId')
                if reply_id and action == 'message':
                    previous = root.collection('messages').document(clean(reply_id,80)).get().to_dict()
                    if previous:
                        item['replyTo'] = {'id': reply_id, 'text': previous['text'], 'kind': previous['kind']}
                ref.create(item)
                if action == 'message':
                    receiver = next((member for member in couple.get('members', []) if member != uid), None)
                    if receiver:
                        sender = (couple.get('names') or {}).get(uid, 'Your partner')
                        preview = ('Invited you to a Metherapy session: ' + text[:300]) if item['kind'] == 'court' else (('Photo: ' + text[:500]) if photo and text else 'Sent a photo' if photo else text[:700])
                        self._send_place_alerts(receiver, [{'title': f'Closer · {sender}', 'text': preview,
                            'type': 'metherapy_invite' if item['kind'] == 'court' else 'chat', 'messageId': item_id, 'sentAt': now}])
            elif action == 'push_unregistration':
                profile_ref.set({'pushIds': []}, merge=True)
            elif action == 'push_registration':
                fid = clean(body.get('installationId'), 4096)
                if len(fid) < 16 or any(char.isspace() for char in fid):
                    raise AccessError(400, 'Invalid notification registration.')
                profile_ref.set({'pushIds': [fid]}, merge=True)
            elif action == 'saved_place_save':
                raw_place = body.get('place')
                if not isinstance(raw_place, dict):
                    raise AccessError(400, 'Invalid saved place.')
                place_id = clean(raw_place.get('id'), 80)
                if not re.fullmatch(r'[A-Za-z0-9_-]{8,80}', place_id):
                    raise AccessError(400, 'Invalid saved place.')
                name = clean(raw_place.get('name'), 50)
                lat, lon = raw_place.get('lat'), raw_place.get('lon')
                radius = raw_place.get('radiusMeters')
                if type(lat) not in (int, float) or type(lon) not in (int, float) or not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180:
                    raise AccessError(400, 'Choose a valid place on the map.')
                if type(radius) is not int or not 50 <= radius <= 5000:
                    raise AccessError(400, 'Choose a place alert radius between 50 and 5,000 metres.')
                notify_arrival = raw_place.get('notifyArrival') is True
                notify_departure = raw_place.get('notifyDeparture') is True
                enabled = raw_place.get('enabled') is True
                if not notify_arrival and not notify_departure:
                    raise AccessError(400, 'Choose an arrival alert, a departure alert, or both.')
                place_ref = root
                @firestore.transactional
                def save_place(tx):
                    current = place_ref.get(transaction=tx).to_dict() or {}
                    places = current.get('savedPlaces', [])
                    previous = next((p for p in places if p.get('id') == place_id), None)
                    record = {
                        'id': place_id, 'name': name, 'lat': lat, 'lon': lon,
                        'radiusMeters': radius, 'notifyArrival': notify_arrival,
                        'notifyDeparture': notify_departure, 'enabled': enabled,
                        'createdBy': previous.get('createdBy', uid) if previous else uid,
                        'updatedAt': now,
                    }
                    updated = [p for p in places if p.get('id') != place_id]
                    updated.append(record)
                    if len(updated) > 100:
                        raise AccessError(400, 'This couple already has 100 saved places.')
                    tx.set(place_ref, {'savedPlaces': updated}, merge=True)
                save_place(self.db.transaction())
            elif action == 'saved_place_delete':
                place_id = clean(body.get('id'), 80)
                place_ref = root
                @firestore.transactional
                def delete_place(tx):
                    current = place_ref.get(transaction=tx).to_dict() or {}
                    places = current.get('savedPlaces', [])
                    tx.set(place_ref, {'savedPlaces': [p for p in places if p.get('id') != place_id]}, merge=True)
                delete_place(self.db.transaction())
            elif action == 'delete_memories':
                ids = body.get('ids')
                if not isinstance(ids, list) or not 1 <= len(ids) <= 500:
                    raise AccessError(400, 'Choose between 1 and 500 memories to delete.')
                ids = [clean(item_id, 80) for item_id in ids]
                if any(not all(c.isalnum() or c in '_-' for c in item_id) for item_id in ids):
                    raise AccessError(400, 'Invalid record.')
                batch = self.db.batch()
                for item_id in set(ids):
                    batch.delete(root.collection('memories').document(item_id))
                batch.commit()
            elif action == 'heart':
                ref = root.collection('messages').document(clean(body.get('id'),80))
                if not ref.get().exists:
                    raise AccessError(404, 'Message unavailable.')
                ref.update({'hearts': firestore.ArrayUnion([uid]) if body.get('liked') is True else firestore.ArrayRemove([uid])})
            elif action == 'anniversary':
                date = clean(body.get('date'), 40)
                datetime.fromisoformat(date)
                root.update({'anniversary': date})
            elif action == 'location':
                if body.get('location') is None:
                    root.update({f'locations.{uid}': firestore.DELETE_FIELD})
                else:
                    point = body['location']
                    lat, lon = point.get('lat'), point.get('lon')
                    if type(lat) not in (int,float) or type(lon) not in (int,float) or not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180:
                        raise AccessError(400, 'Invalid location.')
                    speed = point.get('speedMps')
                    accuracy = point.get('speedAccuracyMps')
                    if type(speed) not in (int, float) or not math.isfinite(speed) or not 0 <= speed <= 100:
                        speed = None
                    if type(accuracy) not in (int, float) or not math.isfinite(accuracy) or accuracy < 0:
                        accuracy = None
                    @firestore.transactional
                    def update_location(tx):
                        current = root.get(transaction=tx).to_dict() or {}
                        old = (current.get('locations') or {}).get(uid)
                        events = []
                        if isinstance(old, dict) and type(old.get('lat')) in (int, float) and type(old.get('lon')) in (int, float):
                            for place in current.get('savedPlaces', []):
                                if not place.get('enabled'):
                                    continue
                                distance_before = self._meters_between(old['lat'], old['lon'], place['lat'], place['lon'])
                                distance_after = self._meters_between(lat, lon, place['lat'], place['lon'])
                                radius = place['radiusMeters']
                                was_inside, is_inside = distance_before <= radius, distance_after <= radius
                                if was_inside == is_inside:
                                    continue
                                if is_inside and place.get('notifyArrival'):
                                    event_type = 'arrived at'
                                elif was_inside and place.get('notifyDeparture'):
                                    event_type = 'left'
                                else:
                                    continue
                                actor = (current.get('names') or {}).get(uid, 'Your partner')
                                events.append({'placeId': place['id'], 'text': f'{actor} {event_type} {place["name"]}.'})
                        tx.update(root, {f'locations.{uid}': {'lat': lat, 'lon': lon, 'speedMps': speed, 'speedAccuracyMps': accuracy, 'updatedAt': now}})
                        return current, events
                    current, events = update_location(self.db.transaction())
                    receiver = next((member_id for member_id in current.get('members', []) if member_id != uid), None)
                    if receiver and events:
                        self._send_place_alerts(receiver, events)
            else:
                raise AccessError(400, 'Unknown action.')
        return self.state(uid)

    def photo(self, uid, payload):
        cid, _ = self.member(uid)
        encoded = payload.get('image_base64')
        if not isinstance(encoded, str) or len(encoded) > 5600000:
            raise AccessError(413, 'Choose a photo smaller than 4 MB.')
        try:
            raw = base64.b64decode(encoded, validate=True)
        except Exception:
            raise AccessError(400, 'Invalid image.')
        if len(raw)>4000000 or not (raw.startswith(b'\xff\xd8\xff') or raw.startswith(b'\x89PNG\r\n\x1a\n')):
            raise AccessError(400, 'Use a JPEG or PNG photo smaller than 4 MB.')
        photo_id=secrets.token_hex(16)
        self.bucket.blob(f'{cid}/{photo_id}').upload_from_string(raw,content_type='image/jpeg' if raw.startswith(b'\xff') else 'image/png')
        self.db.collection('closer_couples').document(cid).collection('photos').document(photo_id).set({'owner':uid})
        return {'id':photo_id}

    def read_photo(self, uid, photo_id):
        cid, _ = self.member(uid)
        if not isinstance(photo_id,str) or not re_photo(photo_id):
            raise AccessError(400, 'Invalid photo.')
        return self.bucket.blob(f'{cid}/{photo_id}').download_as_bytes()

    def tag_memory(self, uid, memory_id, photo_id, api_key, model):
        cid, _ = self.member(uid)
        memory_ref = self.db.collection('closer_couples').document(cid).collection('memories').document(memory_id)
        memory = memory_ref.get().to_dict()
        if not memory or memory.get('photoId') != photo_id:
            raise AccessError(404, 'Memory unavailable.')
        if memory.get('visualTagsVersion') == 2:
            return {'tags': memory['tags']}
        raw = self.read_photo(uid, photo_id)
        mime = 'image/jpeg' if raw.startswith(b'\xff\xd8\xff') else 'image/png'
        prompt = ('Inspect the actual photo and return up to 20 visual search tags. Include visible objects, animals, scenery, product types, and clearly readable text, labels and brand names. For example, ONLY if a Coca-Cola label is visible include coca cola, coca-cola, coke, soda and bottle or can as appropriate. Include singular and plural nouns such as cat and cats. Do not guess unclear brands or unreadable text. '
                  'Use common nouns or simple phrases (for example flowers, car, beach, sunset). '
                  'Do not infer identities, relationships, location, sensitive traits, or anything not clearly visible. '
                  'Return only JSON: {"tags":["..."]}.')
        response = requests.post('https://api.meta.ai/v1/responses', headers={
            'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}, json={
                'model': model, 'store': False, 'input': [{'role': 'user', 'content': [
                    {'type': 'input_text', 'text': prompt},
                    {'type': 'input_image', 'image_url': f'data:{mime};base64,{base64.b64encode(raw).decode()}'}]}]}, timeout=45)
        response.raise_for_status()
        data = response.json()
        text = data.get('output_text', '')
        if not text:
            text = ''.join(part.get('text', '') for output in data.get('output', [])
                           if output.get('type') == 'message' for part in output.get('content', [])
                           if part.get('type') == 'output_text')
        parsed = json.loads(text)
        tags = parsed.get('tags') if isinstance(parsed, dict) else None
        if not isinstance(tags, list):
            raise ValueError('Invalid tag response')
        normalized = list(dict.fromkeys(tag.strip().lower() for tag in tags
                               if isinstance(tag, str) and 0 < len(tag.strip()) <= 32))[:20]
        memory_ref.update({'tags': normalized, 'visualTagsVersion': 2})
        return {'tags': normalized}


def re_photo(value):
    return len(value)==32 and all(c in '0123456789abcdef' for c in value)
