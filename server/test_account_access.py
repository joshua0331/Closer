"""Account access, budget and opening-response regressions; no external APIs."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from account_access import AccountAccess
from demo_security import AccessError, DemoAccess
from demo_storage import SQLiteRecords
from hosted_app import make_app
from shared_court import initial, model_review
from test_shared_court import Data


class AccountAccessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.records = SQLiteRecords(Path(self.temp.name) / 'quota.db')
        self.now = 500000.0
        self.security = DemoAccess(self.records, lambda: self.now)
        self.security.initialize(calls=100, images=1, hours=24)
        self.access = AccountAccess(self.records, 'a', 'pair', lambda: self.now)

    def test_account_needs_no_demo_code_but_charges_budget(self):
        reservation = self.access.reserve('', 'hearing', 'account_request_0001', 'case:0')
        self.access.finish(reservation)
        self.access.finish(reservation)
        self.assertEqual(self.security.policy()['calls_used'], 1)
        self.assertEqual(self.security.policy()['leases'], {})
        with self.assertRaises(AccessError):
            self.access.reserve('', 'hearing', 'account_request_0001', 'case:0')
        self.assertEqual(self.security.policy()['calls_used'], 1)

    def test_global_disable_and_image_budget_are_preserved(self):
        reservation = self.access.reserve('', 'characters', 'account_request_0001', 'art')
        self.access.finish(reservation)
        with self.assertRaises(AccessError):
            self.access.reserve('', 'characters', 'account_request_0002', 'art2')
        self.security.set_enabled(False)
        with self.assertRaises(AccessError):
            self.access.reserve('', 'hearing', 'account_request_0003', 'text')

    def test_pair_limit_cannot_be_reset_by_switching_partners(self):
        other = AccountAccess(self.records, 'b', 'pair', lambda: self.now)
        for index in range(40):
            self.now += 61
            access = other if index % 2 else self.access
            reservation = access.reserve('', 'hearing', f'account_request_{index:04}', str(index))
            access.finish(reservation)
        self.now += 61
        with self.assertRaises(AccessError):
            other.reserve('', 'hearing', 'account_request_0040', 'overflow')
        self.assertEqual(self.security.policy()['calls_used'], 40)

    def test_opening_is_saved_without_entering_portrait_branch(self):
        data = Data()
        state = initial(data.couple, data.message)
        state.update(joined=['a', 'b'], aiConsent=['a', 'b'], facilitatorPending=True)
        data.db.values['closer_couples/c/hearings/case1'] = state
        with patch('shared_court.firestore.transactional', lambda fn: fn), patch('shared_court.call_hearing', return_value={'model': 'muse-spark-1.3', 'result': {'message': 'Let us hear both sides.'}}) as upstream:
            result = model_review(data, 'a', 'case1', {'operation': 'opening', 'version': 0}, 'test-key', 'muse-spark-1.3', self.access, '', 'account_request_0001')
        self.assertTrue(result['openingResponseDone'])
        self.assertEqual(result['facilitatorResponses'][0]['message'], 'Let us hear both sides.')
        self.assertIsNone(result['lease'])
        upstream.assert_called_once()

    def test_account_session_route_uses_identity_without_demo_header(self):
        with TestClient(make_app(records=self.records, api_key='test-key', clock=lambda: self.now)) as client:
            data = Mock()
            data.user.return_value = 'a'
            data.member.return_value = ('pair', {})
            client.app.state.couple_data = data
            with patch('shared_court.model_review', return_value={'phase': 0}) as review:
                response = client.post('/couple/court/case1', headers={'Authorization': 'Bearer valid-test-identity', 'X-Request-ID': 'account_request_0001'}, json={'operation': 'opening', 'version': 0})
                self.assertEqual(response.status_code, 200)
                self.assertIsInstance(review.call_args.args[6], AccountAccess)
            data.user.side_effect = AccessError(401, 'Invalid identity')
            with patch('shared_court.model_review') as review:
                response = client.post('/couple/court/case1', headers={'Authorization': 'Bearer invalid'}, json={'operation': 'opening', 'version': 0})
                self.assertEqual(response.status_code, 401)
                review.assert_not_called()

    def test_unpair_clears_pair_and_old_avatar_for_both_people(self):
        from couple_data import CoupleData, firestore
        data = Data()
        data.db.values.update({
            'closer_profiles/a': {'coupleId': 'c', 'avatarPhotoId': 'old_a'},
            'closer_profiles/b': {'coupleId': 'c', 'avatarPhotoId': 'old_b'},
            'closer_couples/c': {'members': ['a', 'b'], 'locations': {'a': {}}, 'savedPlaces': [{}]},
        })
        store = CoupleData.__new__(CoupleData)
        store.db = data.db
        with patch('couple_data.firestore.transactional', lambda fn: fn):
            result = store.action('a', {'action': 'unpair'})
        self.assertTrue(result['unpaired'])
        for uid in ['a', 'b']:
            profile = data.db.values[f'closer_profiles/{uid}']
            self.assertEqual(repr(profile['coupleId']), repr(firestore.DELETE_FIELD))
            self.assertEqual(repr(profile['avatarPhotoId']), repr(firestore.DELETE_FIELD))
        self.assertEqual(data.db.values['closer_couples/c']['members'], [])
        self.assertEqual(data.db.values['closer_couples/c']['locations'], {})


if __name__ == '__main__':
    unittest.main()
