"""Authenticated WebRTC signaling for a two-partner Metherapy voice call.

Audio stays peer-to-peer and is never written to Firestore. Only the offer,
answer, and short-lived ICE candidates are stored for call setup.
"""
import re
import secrets
import time

from google.cloud import firestore
from demo_security import AccessError
from shared_court import ref_for

MAX_SDP = 24000
MAX_CANDIDATE = 4000


def _call_ref(data, uid, case_id):
    root, hearing_ref, couple, message = ref_for(data, uid, case_id)
    hearing = hearing_ref.get().to_dict()
    if not hearing or uid not in hearing.get('people', []):
        raise AccessError(403, 'You are not part of this session.')
    if len(set(hearing.get('joined', []))) != 2:
        raise AccessError(409, 'Both partners must enter the session before starting a call.')
    return root.collection('hearing_calls').document(case_id), hearing


def _clean_sdp(value):
    if not isinstance(value, str) or not value.strip() or len(value) > MAX_SDP:
        raise AccessError(400, 'Invalid call connection data.')
    return value


def state(data, uid, case_id, after=0):
    ref, hearing = _call_ref(data, uid, case_id)
    if not isinstance(after, int) or after < 0:
        raise AccessError(400, 'Invalid call cursor.')
    call = ref.get().to_dict()
    if not call:
        return {'status': 'not_started', 'signals': [], 'nextSignal': after}
    if uid not in call.get('members', []):
        raise AccessError(403, 'You are not part of this call.')
    signals = [
        doc for doc in ref.collection('signals').where('sequence', '>', after)
        .order_by('sequence').limit(100).stream()
        if doc.to_dict().get('callId') == call.get('callId')
    ]
    return {
        'callId': call.get('callId'),
        'status': call.get('status', 'waiting'),
        'members': call.get('members', []),
        'joined': call.get('joined', []),
        'startedBy': call.get('startedBy'),
        'offer': call.get('offer'),
        'answer': call.get('answer'),
        'signals': [{'id': doc.id, **doc.to_dict()} for doc in signals],
        'nextSignal': call.get('nextSignal', after),
    }


def update(data, uid, case_id, body):
    if not isinstance(body, dict):
        raise AccessError(400, 'Invalid call request.')
    ref, hearing = _call_ref(data, uid, case_id)
    operation = body.get('operation')
    people = list(hearing['people'])
    if uid not in people:
        raise AccessError(403, 'You are not part of this session.')

    if hearing.get('phase') == 18 and operation != 'end':
        raise AccessError(409, 'This session has ended.')

    if operation == 'join':
        if body.get('aiConsent') is not True:
            raise AccessError(400, 'Joining requires the displayed Meta AI consent.')
        now = time.time()

        @firestore.transactional
        def join_call(tx):
            call = ref.get(transaction=tx).to_dict()
            if not call or call.get('status') == 'ended':
                call = {
                    'callId': secrets.token_hex(12),
                    'members': people,
                    'startedBy': uid,
                    'joined': [uid],
                    'aiConsent': [uid],
                    'audioConsent': [uid] if body.get('audioConsent') is True else [],
                    'readyAt': {},
                    'status': 'waiting',
                    'offer': None,
                    'answer': None,
                    'nextSignal': 0,
                    'createdAt': now,
                    'endedAt': None,
                }
                tx.set(ref, call)
                return call
            if uid not in call.get('members', []):
                raise AccessError(403, 'You are not part of this call.')
            joined = list(dict.fromkeys(call.get('joined', []) + [uid]))
            if body.get('audioConsent') is True:
                call['audioConsent'] = list(set(call.get('audioConsent', []) + [uid]))
            call['aiConsent'] = list(set(call.get('aiConsent', []) + [uid]))
            call.update(joined=joined, status='connected' if len(joined) == 2 else 'waiting')
            tx.set(ref, call)
            return call
        return join_call(data.db.transaction())

    call = ref.get().to_dict()
    if not call or call.get('status') == 'ended':
        raise AccessError(409, 'Start or join the voice call first.')
    if uid not in call.get('members', []) or uid not in call.get('joined', []):
        raise AccessError(403, 'Join this call before sending connection data.')
    call_id = body.get('callId')
    if call_id != call.get('callId'):
        raise AccessError(409, 'This call has ended. Rejoin to start a new one.')

    if operation == 'ready':
        hearing_ref = ref.parent.parent.collection('hearings').document(case_id)
        @firestore.transactional
        def mark_ready(tx):
            current = ref.get(transaction=tx).to_dict() or {}
            session = hearing_ref.get(transaction=tx).to_dict() or {}
            if (session.get('phase') == 18 or current.get('status') == 'ended'
                    or current.get('callId') != call_id or uid not in current.get('aiConsent', [])):
                raise AccessError(409, 'Join the call with consent first.')
            now = time.time()
            ready = dict(current.get('readyAt', {}))
            ready[uid] = now
            tx.update(ref, {'readyAt': ready})
            both_ready = all(now - ready.get(person, 0) < 15 for person in people)
            if both_ready and not session.get('openingResponseDone') and not session.get('facilitatorPending'):
                session.update(aiConsent=people, facilitatorPending=True, deadline=None,
                               openingTriggerBy=uid, version=session.get('version', 0) + 1,
                               voiceStartedAt=now)
                tx.set(hearing_ref, session)
            elif (both_ready and session.get('openingResponseDone') and not session.get('conclusionOffered')
                  and not session.get('facilitatorPending') and not session.get('playbackPending') and not session.get('lease') and not (session.get('audioLease') or {}).get('until',0) > now
                  and session.get('phase', 18) <= 12 and now - session.get('voiceStartedAt', now) >= 300):
                session.update(conclusionPending=True, facilitatorPending=True, deadline=None,
                               version=session.get('version', 0) + 1)
                tx.set(hearing_ref, session)
            return {'ok': True}
        return mark_ready(data.db.transaction())

    if operation in {'offer', 'answer'}:
        sdp = _clean_sdp(body.get('sdp'))
        if operation == 'offer' and uid != call.get('startedBy'):
            raise AccessError(403, 'Only the caller can send the offer.')
        if operation == 'answer' and uid == call.get('startedBy'):
            raise AccessError(403, 'The other partner must answer the call.')
        field = operation

        @firestore.transactional
        def save_description(tx):
            current = ref.get(transaction=tx).to_dict()
            if not current or current.get('status') == 'ended' or current.get('callId') != call_id:
                raise AccessError(409, 'This call has ended. Rejoin to start a new one.')
            if uid not in current.get('joined', []):
                raise AccessError(403, 'Join this call before sending connection data.')
            if operation == 'offer' and uid != current.get('startedBy'):
                raise AccessError(403, 'Only the caller can send the offer.')
            if operation == 'answer' and uid == current.get('startedBy'):
                raise AccessError(403, 'The other partner must answer the call.')
            tx.update(ref, {field: {
                'type': operation,
                'sdp': sdp,
                'sender': uid,
                'createdAt': time.time(),
            }})
            return {'ok': True}

        return save_description(data.db.transaction())

    if operation == 'candidate':
        candidate = body.get('candidate')
        if not isinstance(candidate, dict):
            raise AccessError(400, 'Invalid call connection data.')
        line = candidate.get('sdpMLineIndex')
        text = candidate.get('candidate')
        mid = candidate.get('sdpMid')
        if (not isinstance(text, str) or not text or len(text) > MAX_CANDIDATE
                or (mid is not None and (not isinstance(mid, str) or len(mid) > 128))
                or (line is not None and (not isinstance(line, int) or line < 0 or line > 100))):
            raise AccessError(400, 'Invalid call connection data.')

        @firestore.transactional
        def add_candidate(tx):
            current = ref.get(transaction=tx).to_dict()
            if not current or current.get('status') == 'ended' or current.get('callId') != call_id:
                raise AccessError(409, 'This call has ended. Rejoin to start a new one.')
            sequence = int(current.get('nextSignal', 0)) + 1
            signal_ref = ref.collection('signals').document(f'{sequence:06d}')
            tx.set(signal_ref, {'sequence': sequence, 'callId': call_id, 'sender': uid, 'candidate': candidate, 'createdAt': time.time()})
            tx.update(ref, {'nextSignal': sequence})
            return {'ok': True, 'sequence': sequence}
        return add_candidate(data.db.transaction())

    if operation == 'end':
        ref.update({
            'status': 'ended',
            'endedAt': time.time(),
            'endedBy': uid,
            'offer': None,
            'answer': None,
        })
        for signal in ref.collection('signals').stream():
            signal.reference.delete()
        return {'ok': True}

    raise AccessError(400, 'Unknown call action.')