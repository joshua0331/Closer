"""Authenticated shared couple data. Separate collections; no client DB access."""
import base64
import hashlib
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
        try:
            claims = id_token.verify_firebase_token(token, _CERT_REQUEST, audience=self.project)
            uid = claims['sub']
            if not uid or len(uid) > 128:
                raise ValueError()
            return uid
        except Exception:
            raise AccessError(401, 'Please sign in again.')

    def admit(self, uid, photo=False):
        ref = self.db.collection('closer_app_limits').document(uid)
        now = int(time.time())
        @firestore.transactional
        def reserve(tx):
            record = ref.get(transaction=tx).to_dict() or {}
            minute, day = now // 60, now // 86400
            calls = record.get('calls', 0) if record.get('minute') == minute else 0
            photos = record.get('photos', 0) if record.get('day') == day else 0
            if calls >= 90 or (photo and photos >= 20):
                raise AccessError(429, 'Please wait before uploading or syncing again.')
            tx.set(ref, {'minute': minute, 'calls': calls+1, 'day': day, 'photos': photos + int(photo)})
        reserve(self.db.transaction())

    def member(self, uid):
        profile = self.db.collection('closer_profiles').document(uid).get().to_dict() or {}
        cid = profile.get('coupleId')
        if not cid:
            raise AccessError(409, 'Pair with your partner first.')
        couple = self.db.collection('closer_couples').document(cid).get().to_dict()
        if not couple or uid not in couple['members']:
            raise AccessError(403, 'This shared space is unavailable.')
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
        return {'profile': profile, 'couple': {'id': cid, **couple},
                'messages': list(reversed(records('messages'))), 'memories': records('memories')}

    def action(self, uid, body):
        if not isinstance(body, dict):
            raise AccessError(400, 'Invalid request.')
        action = body.get('action')
        profile_ref = self.db.collection('closer_profiles').document(uid)
        now = datetime.now(timezone.utc).isoformat()
        if action == 'profile':
            name = clean(body.get('name'), 50)
            profile_ref.set({'name': name}, merge=True)
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
                tx.set(couple_ref, {'members': [owner, uid], 'names': {owner: profiles[1]['name'], uid: profiles[0]['name']}, 'createdAt': now, 'locations': {}})
                tx.update(profile_ref, {'coupleId': couple_ref.id})
                tx.update(owner_ref, {'coupleId': couple_ref.id})
                tx.update(invite_ref, {'used': True})
            pair(self.db.transaction())
        else:
            cid, couple = self.member(uid)
            root = self.db.collection('closer_couples').document(cid)
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
                if action == 'message' and body.get('summons') is True:
                    item.update(kind='court', status='open')
                reply_id = body.get('replyId')
                if reply_id and action == 'message':
                    previous = root.collection('messages').document(clean(reply_id,80)).get().to_dict()
                    if previous:
                        item['replyTo'] = {'id': reply_id, 'text': previous['text'], 'kind': previous['kind']}
                ref.create(item)
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
                    if type(lat) not in (int,float) or type(lon) not in (int,float) or not -90 <= lat <= 90 or not -180 <= lon <= 180:
                        raise AccessError(400, 'Invalid location.')
                    root.update({f'locations.{uid}': {'lat': lat, 'lon': lon, 'updatedAt': now}})
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


def re_photo(value):
    return len(value)==32 and all(c in '0123456789abcdef' for c in value)
