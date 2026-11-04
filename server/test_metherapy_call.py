import copy
import json
import time
import unittest
from unittest.mock import Mock, patch
from demo_security import AccessError
from live_call import update
from court_protocol import call_hearing
from test_court_protocol import CASE

class VoiceSessionTests(unittest.TestCase):
    def setup_call(self, elapsed=0, opened=False):
        now = time.time()
        self.session = {'people':['a','b'], 'joined':['a','b'], 'phase':1,
                        'version':3, 'openingResponseDone':opened,
                        'voiceStartedAt':now-elapsed, 'facilitatorPending':False}
        self.call = {'callId':'test', 'members':['a','b'], 'joined':['a','b'],
                     'aiConsent':['a','b'], 'status':'connected', 'readyAt':{'a':now,'b':now}}
        self.ref = Mock()
        self.ref.get.return_value.to_dict.side_effect = lambda: copy.deepcopy(self.call)
        self.hearing_ref = self.ref.parent.parent.collection.return_value.document.return_value
        self.hearing_ref.get.return_value.to_dict.side_effect = lambda: copy.deepcopy(self.session)
        self.data = Mock()
        self.tx = self.data.db.transaction.return_value
        self.tx.set.side_effect = lambda ref, value: self.session.update(value)

    def test_ready_opens_once_after_both_connect(self):
        self.setup_call()
        with patch('live_call._call_ref', return_value=(self.ref, self.session)), patch('live_call.firestore.transactional', lambda fn:fn):
            update(self.data,'a','case',{'operation':'ready','callId':'test'})
            self.assertTrue(self.session['facilitatorPending'])
            self.assertEqual(self.session['aiConsent'], ['a','b'])
            update(self.data,'a','case',{'operation':'ready','callId':'test'})
        self.assertEqual(self.tx.set.call_count,1)

    def test_five_minute_checkin_is_queued_once(self):
        self.setup_call(301, True)
        with patch('live_call._call_ref', return_value=(self.ref,self.session)), patch('live_call.firestore.transactional',lambda fn:fn):
            update(self.data,'a','case',{'operation':'ready','callId':'test'})
            self.assertTrue(self.session['conclusionPending'])
            self.assertIsNone(self.session['deadline'])
            update(self.data,'b','case',{'operation':'ready','callId':'test'})
        self.assertEqual(self.tx.set.call_count,1)

    def test_join_without_disclosure_consent_is_rejected(self):
        self.setup_call()
        with patch('live_call._call_ref',return_value=(self.ref,self.session)):
            with self.assertRaises(AccessError):
                update(self.data,'a','case',{'operation':'join'})

    @patch('court_protocol.urlopen')
    def test_five_minute_prompt_asks_for_mutual_next_steps(self, opener):
        opener.return_value.__enter__.return_value.read.return_value=json.dumps({
            'status':'completed','model':'muse-spark-1.3','output':[{'type':'message','role':'assistant',
            'content':[{'type':'output_text','text':json.dumps({'message':'What small step would you both like to try?', 'evidenceReview':[]})}]}]}).encode()
        case={**CASE,'sessionElapsedSeconds':301,'evidence':[]}
        call_hearing({'action':'reflection','case':case},'test','muse-spark-1.3')
        body=json.loads(opener.call_args.args[0].data)
        self.assertIn('voluntary conclusion', body['input'][0]['content'][1]['text'])
