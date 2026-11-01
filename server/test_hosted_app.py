import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import URLError
from fastapi.testclient import TestClient
from demo_security import DemoAccess
from demo_storage import SQLiteRecords
from hosted_app import make_app

CASE = {'topic': 'Chores', 'names': ['Alex', 'Sam'], 'statements': ['Dishes', 'Laundry']}


class HostedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        records = SQLiteRecords(Path(self.temp.name) / 'quota.db')
        self.security = DemoAccess(records)
        self.security.initialize(calls=5, images=1, hours=24)
        self.invite = self.security.create_invite('Judge', calls=2, images=1)
        self.client = self.enterContext(TestClient(make_app(records=records, api_key='private-test-meta-key')))

    def test_web_preflight_and_auth_are_separate(self):
        headers = {'Origin': 'https://closer-court-ddf3a.web.app',
                   'Access-Control-Request-Method': 'POST',
                   'Access-Control-Request-Headers': 'authorization,x-demo-session,x-request-id,content-type'}
        response = self.client.options('/couple/action', headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers['access-control-allow-origin'], headers['Origin'])
        response = self.client.get('/couple/state', headers={'Origin': headers['Origin']})
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.headers['access-control-allow-origin'], headers['Origin'])
        headers['Origin'] = 'https://untrusted.example'
        self.assertEqual(self.client.options('/couple/action', headers=headers).status_code, 400)

    def connect(self):
        response = self.client.post('/auth/session', json={'code': self.invite['code']})
        self.assertEqual(response.status_code, 200)
        return response.json()['session_token']

    def headers(self, token, request_id='hosted_request_0001'):
        return {'Authorization': f'Bearer {token}', 'X-Request-ID': request_id}

    @patch('hosted_app.call_meta')
    def test_only_session_auth_reaches_meta_and_duplicate_is_blocked(self, upstream):
        upstream.return_value = {'verdict': 'Share the task.', 'model': 'muse-spark-1.3'}
        for token in ['', 'static-app-token', self.invite['code']]:
            response = self.client.post('/judge', json=CASE, headers=self.headers(token))
            self.assertEqual(response.status_code, 401)
        upstream.assert_not_called()
        token = self.connect()
        response = self.client.post('/judge', json=CASE, headers=self.headers(token))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['model'], 'muse-spark-1.3')
        self.assertEqual(upstream.call_args.args[1], 'private-test-meta-key')
        self.assertNotIn('private-test-meta-key', response.text)
        self.assertEqual(self.client.post('/judge', json=CASE, headers=self.headers(token)).status_code, 409)
        self.assertEqual(upstream.call_count, 1)

    @patch('hosted_app.call_meta', side_effect=URLError('provider failure'))
    def test_failures_count_conservatively_and_usage_cap_blocks_more_calls(self, upstream):
        token = self.connect()
        for index in range(2):
            response = self.client.post('/judge', json=CASE, headers=self.headers(token, f'failed_request_{index:04}'))
            self.assertEqual(response.status_code, 502)
        response = self.client.post('/judge', json=CASE, headers=self.headers(token, 'blocked_request_0003'))
        self.assertEqual(response.status_code, 429)
        self.assertEqual(upstream.call_count, 2)
        self.assertEqual(self.security.policy()['calls_used'], 2)

    @patch('hosted_app.call_meta')
    def test_invalid_and_oversized_bodies_never_spend_meta_calls(self, upstream):
        token = self.connect()
        self.assertEqual(self.client.post('/judge', json={}, headers=self.headers(token)).status_code, 400)
        headers = {**self.headers(token), 'Content-Type': 'application/json'}
        self.assertEqual(self.client.post('/judge', content='x' * 33000, headers=headers).status_code, 413)
        upstream.assert_not_called()
        self.assertEqual(self.security.policy()['calls_used'], 0)
        self.assertEqual(self.client.get('/docs').status_code, 404)
        self.assertEqual(self.client.get('/api/health').json(), {'status': 'ready'})

    @patch('hosted_app.segment_evidence')
    def test_sam_requires_session_and_reserves_total_budget(self, upstream):
        from test_court_protocol import PHOTO
        payload = {'image_base64': PHOTO, 'prompt': 'plate'}
        upstream.return_value = {'model': 'sam-3.1', 'prompt': 'plate', 'boxes': []}
        self.assertEqual(self.client.post('/segment', json=payload).status_code, 401)
        upstream.assert_not_called()
        token = self.connect()
        headers = self.headers(token)
        self.assertEqual(self.client.post('/segment', json=payload, headers=headers).status_code, 200)
        self.assertEqual(self.security.policy()['calls_used'], 1)
        self.assertEqual(self.security.policy()['images_used'], 0)
        self.assertEqual(self.client.post('/segment', json=payload, headers=headers).status_code, 409)
        self.assertEqual(upstream.call_count, 1)

    @patch('hosted_app.call_meta')
    def test_revoke_and_disable_stop_existing_sessions(self, upstream):
        token = self.connect()
        self.security.revoke(self.invite['id'])
        self.assertEqual(self.client.post('/judge', json=CASE, headers=self.headers(token)).status_code, 401)
        self.security.set_enabled(False)
        self.assertEqual(self.client.post('/judge', json=CASE, headers=self.headers(token)).status_code, 503)
        upstream.assert_not_called()

if __name__ == '__main__':
    unittest.main()
