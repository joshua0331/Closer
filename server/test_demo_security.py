from contextlib import closing
import concurrent.futures
import tempfile
import unittest
from pathlib import Path
from demo_security import AccessError, DemoAccess
from demo_storage import SQLiteRecords


class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'demo.db'
        self.now = 1000000.0
        self.security = DemoAccess(SQLiteRecords(self.path), lambda: self.now)
        self.security.initialize(calls=10, images=2, hours=24)

    def invite(self, **kwargs):
        return self.security.create_invite('Judges', **kwargs)

    def token(self, invite):
        return self.security.issue(invite['code'])['session_token']

    def call(self, token, nonce='request_0000000001', op='hearing'):
        result = self.security.reserve(token, op, nonce, 'body-digest')
        self.security.finish(result)
        return result

    def test_opaque_sessions_and_hashed_codes(self):
        invite = self.invite()
        token = self.token(invite)
        self.assertNotEqual(token, invite['code'])
        import sqlite3
        with closing(sqlite3.connect(self.path)) as db:
            stored = str(db.execute('SELECT * FROM records').fetchall())
        self.assertNotIn(invite['code'], stored)
        self.assertNotIn(token, stored)
        self.call(token)

    def test_quota_survives_new_sessions_and_restarts(self):
        invite = self.invite(calls=1, sessions=3)
        self.call(self.token(invite))
        restarted = DemoAccess(SQLiteRecords(self.path), lambda: self.now)
        token = restarted.issue(invite['code'])['session_token']
        with self.assertRaises(AccessError) as caught:
            restarted.reserve(token, 'hearing', 'another_request_0002', 'digest')
        self.assertEqual(caught.exception.status, 429)
        self.assertEqual(restarted.policy()['calls_used'], 1)
        with self.assertRaises(ValueError):
            restarted.initialize()

    def test_replay_and_inflight_never_reserve_twice(self):
        token = self.token(self.invite())
        reservation = self.security.reserve(token, 'hearing', 'request_0000000001', 'digest')
        for nonce in ['request_0000000001', 'request_0000000002']:
            with self.assertRaises(AccessError) as caught:
                self.security.reserve(token, 'hearing', nonce, 'digest')
            self.assertEqual(caught.exception.status, 409)
        self.security.finish(reservation)
        with self.assertRaises(AccessError):
            self.security.reserve(token, 'hearing', 'request_0000000001', 'digest')
        self.assertEqual(self.security.policy()['calls_used'], 1)

    def test_image_budget_is_separate_and_revocation_is_immediate(self):
        invite = self.invite(calls=4, images=1)
        token = self.token(invite)
        self.call(token, 'image_request_0001', 'characters')
        with self.assertRaises(AccessError):
            self.call(token, 'image_request_0002', 'characters')
        self.call(token, 'text_request_00003')
        self.security.revoke(invite['id'])
        with self.assertRaises(AccessError) as caught:
            self.call(token, 'text_request_00004')
        self.assertEqual(caught.exception.status, 401)

    def test_expiry_disable_and_session_limit(self):
        invite = self.invite(sessions=1)
        token = self.token(invite)
        with self.assertRaises(AccessError):
            self.token(invite)
        self.security.set_enabled(False)
        with self.assertRaises(AccessError) as caught:
            self.call(token)
        self.assertEqual(caught.exception.status, 503)
        self.security.set_enabled(True)
        self.now += 8 * 3600 + 1
        with self.assertRaises(AccessError):
            self.call(token)

    def test_bruteforce_rate_and_atomic_global_cap(self):
        for _ in range(10):
            with self.assertRaises(AccessError):
                self.security.issue('invalid')
        with self.assertRaises(AccessError) as caught:
            self.security.issue('invalid')
        self.assertEqual(caught.exception.status, 429)
        self.now += 61
        # One shared invite, separate sessions, same durable global counter.
        invite = self.invite(calls=10, sessions=10)
        tokens = [self.token(invite) for _ in range(6)]
        def limit(state):
            policy = state['policy']
            policy['calls_limit'] = 2
            return None, {'policy': policy}
        self.security.records.transaction(['policy'], limit)
        def attempt(index):
            try:
                self.call(tokens[index], f'parallel_request_{index:04}')
                return True
            except AccessError:
                return False
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            passed = list(pool.map(attempt, range(6)))
        self.assertEqual(sum(passed), 2)
        self.assertEqual(self.security.policy()['calls_used'], 2)

if __name__ == '__main__':
    unittest.main()
