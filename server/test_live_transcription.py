import time
import unittest
from unittest.mock import patch
from demo_security import AccessError
from live_transcription import admit_stream, release_stream, validate_pcm
from shared_court import update
from test_shared_court import Data, initial

class TranscriptionTests(unittest.TestCase):
    def setUp(self):
        self.data=Data()
        self.path='closer_couples/c/hearings/case1'
        self.callpath='closer_couples/c/hearing_calls/case1'
        state=initial(self.data.couple,self.data.message)
        state.update(joined=['a','b'],openingResponseDone=True,deadline=time.time()+120,aiConsent=['a','b'])
        self.data.db.values[self.path]=state
        self.data.db.values[self.callpath]={'status':'connected','offer':True,'answer':True,
            'readyAt':{'a':time.time(),'b':time.time()},'audioConsent':['a','b']}
        for module in ('live_transcription','shared_court'):
            p=patch(module+'.firestore.transactional',lambda fn:fn);p.start();self.addCleanup(p.stop)
    def test_only_active_speaker_can_stream(self):
        with self.assertRaises(AccessError):admit_stream(self.data,'b','case1',0,'one')
        admit_stream(self.data,'a','case1',0,'one')
        with self.assertRaises(AccessError):admit_stream(self.data,'a','case1',0,'two')
        release_stream(self.data,'a','case1','one')
        admit_stream(self.data,'a','case1',0,'two')
    def test_audio_consent_required_from_both(self):
        self.data.db.values[self.callpath]['audioConsent']=['a']
        with self.assertRaises(AccessError):admit_stream(self.data,'a','case1',0,'one')
    def test_no_capture_during_ai_playback(self):
        self.data.db.values[self.path]['playbackPending']=['b']
        with self.assertRaises(AccessError):admit_stream(self.data,'a','case1',0,'one')
    def test_pcm_bounds(self):
        validate_pcm(bytes(2560),0)
        for frame,total in [(b'',0),(b'x',0),(bytes(6402),0),(bytes(2560),4_000_000)]:
            with self.assertRaises(AccessError):validate_pcm(frame,total)
    def test_both_playback_acks_and_duplicate_is_idempotent(self):
        self.data.db.values[self.path].update(playbackPending=['a','b'],playbackId='reply',deadline=None)
        first=update(self.data,'a','case1',{'operation':'speech_done','playbackId':'reply'})
        self.assertIsNone(first['deadline'])
        repeated=update(self.data,'a','case1',{'operation':'speech_done','playbackId':'reply'})
        self.assertEqual(first['version'],repeated['version'])
        last=update(self.data,'b','case1',{'operation':'speech_done','playbackId':'reply'})
        self.assertGreater(last['deadline'],time.time())
