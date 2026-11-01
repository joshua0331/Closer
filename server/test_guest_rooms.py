import base64
import copy
import hashlib
import secrets
import time
import unittest
from unittest.mock import MagicMock, patch
from couple_data import CoupleData
from demo_security import AccessError, DemoAccess
from demo_storage import SQLiteRecords
from shared_court import update
import tempfile
from pathlib import Path

IMAGE = base64.b64encode(b'\x89PNG\r\n\x1a\n' + b'test-image').decode()
class Snap:
    def __init__(self, value): self.value = value
    def to_dict(self): return copy.deepcopy(self.value)
class Ref:
    def __init__(self, db, path): self.db, self.path, self.id = db, path, path.split('/')[-1]
    def get(self, transaction=None): return Snap(self.db.rows.get(self.path))
    def collection(self, name): return Collection(self.db, self.path + '/' + name)
class Collection:
    def __init__(self, db, path): self.db, self.path = db, path
    def document(self, name=None): return Ref(self.db, self.path + '/' + (name or secrets.token_hex(8)))
class DB:
    def __init__(self): self.rows = {}
    def collection(self, name): return Collection(self, name)
    def transaction(self): return self
    def batch(self): return self
    def commit(self): pass
    def set(self, ref, value): self.rows[ref.path] = copy.deepcopy(value)
    def update(self, ref, value):
        for key, val in value.items():
            target = self.rows[ref.path]
            pieces = key.split('.')
            for piece in pieces[:-1]: target = target.setdefault(piece, {})
            target[pieces[-1]] = copy.deepcopy(val)

class GuestRoomTests(unittest.TestCase):
    def setUp(self):
        patcher = patch('couple_data.firestore.transactional', lambda fn: fn)
        patcher.start(); self.addCleanup(patcher.stop)
        self.data = CoupleData.__new__(CoupleData)
        self.data.db, self.data.bucket = DB(), MagicMock()
        self.fields = {'name': 'Alex', 'image_base64': IMAGE, 'consent': True, 'topic': 'Dishes'}
    def test_no_account_room_has_distinct_private_seats_and_single_use_invite(self):
        host = self.data.room_enter(self.fields)
        guest = self.data.room_enter({**self.fields, 'name': 'Sam', 'code': host['invite']}, True)
        self.assertNotEqual(host['uid'], guest['uid'])
        self.assertEqual(host['roomId'], guest['roomId'])
        self.assertEqual(self.data.user(host['session']), host['uid'])
        self.assertEqual(self.data.user(guest['session']), guest['uid'])
        cid, room = self.data.member(host['uid'])
        self.assertEqual(room['names'][guest['uid']], 'Sam')
        hearing = self.data.db.rows[f'closer_couples/{cid}/hearings/hearing']
        self.assertEqual(hearing['names'], ['Alex', 'Sam'])
        self.assertTrue(all(hearing['portraits']))
        self.assertNotIn(host['session'], repr(self.data.db.rows))
        self.assertNotIn(host['invite'], repr(self.data.db.rows))
        with self.assertRaises(AccessError): self.data.room_enter({**self.fields, 'code': host['invite']}, True)
        with self.assertRaises(AccessError): self.data.user('room_' + 'unknown' * 6)
    def test_expired_invitation_and_session_are_rejected(self):
        host = self.data.room_enter(self.fields)
        invite_key = 'court_room_invites/' + hashlib.sha256(host['invite'].encode()).hexdigest()
        self.data.db.rows[invite_key]['expires'] = 0
        with self.assertRaises(AccessError): self.data.room_enter({**self.fields, 'code': host['invite']}, True)
        session_key = 'court_room_sessions/' + hashlib.sha256(host['session'].encode()).hexdigest()
        self.data.db.rows[session_key]['expires'] = 0
        with self.assertRaises(AccessError): self.data.user(host['session'])
    def test_selfie_consent_required_and_room_sessions_cannot_create_other_spaces(self):
        for fields in [{**self.fields, 'consent': False}, {**self.fields, 'image_base64': 'not an image'}, {**self.fields, 'name': ''}]:
            with self.assertRaises(AccessError): self.data.room_enter(fields)
        host = self.data.room_enter(self.fields)
        with self.assertRaises(AccessError): self.data.action(host['uid'], {'action': 'invite'})
        with self.assertRaises(AccessError): self.data.action(host['uid'], {'action': 'message', 'summons': True})
    def test_room_rate_limit_is_durable(self):
        for _ in range(12): self.data.room_admit('test-client')
        with self.assertRaises(AccessError): self.data.room_admit('test-client')
    def test_new_ai_sessions_share_the_same_room_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            access = DemoAccess(SQLiteRecords(Path(directory) / 'quota.db'))
            access.initialize(calls=20, images=2, hours=24)
            for index in range(8):
                session = access.room_session('room-test', time.time() + 3600)
                reservation = access.reserve(session['session_token'], 'hearing', secrets.token_urlsafe(18), str(index))
                access.finish(reservation)
            session = access.room_session('room-test', time.time() + 3600)
            with self.assertRaises(AccessError): access.reserve(session['session_token'], 'hearing', secrets.token_urlsafe(18), 'over-budget')
            self.assertEqual(access.policy()['calls_used'], 8)
    def test_pre_hearing_evidence_allowed_but_someone_elses_photo_is_rejected(self):
        host = self.data.room_enter(self.fields)
        ref = f"closer_couples/{host['roomId']}/hearings/hearing"
        state = self.data.db.rows[ref]
        photo = state['portraits'][0]
        state = update(self.data, host['uid'], 'hearing', {'operation': 'evidence', 'version': state['version'], 'photoId': photo, 'caption': 'Visible test object'})
        self.assertEqual(len(state['evidence']), 1)
        self.assertEqual(state['joined'], [])
        with self.assertRaises(AccessError): update(self.data, host['uid'], 'hearing', {'operation': 'evidence', 'version': state['version'], 'photoId': 'f' * 32, 'caption': 'Unavailable'})
