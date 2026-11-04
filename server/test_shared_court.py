import time
import copy
import unittest
from unittest.mock import patch
from shared_court import update, initial
from demo_security import AccessError

class Snapshot:
    def __init__(self,value):self.value=value
    def to_dict(self):return copy.deepcopy(self.value)
class Ref:
    def __init__(self,db,path):self.db,self.path=db,path;self.id=path.split('/')[-1]
    def collection(self,name):return Collection(self.db,self.path+'/'+name)
    def get(self,transaction=None):return Snapshot(self.db.values.get(self.path))
class Collection:
    def __init__(self,db,path):self.db,self.path=db,path
    def document(self,name):return Ref(self.db,self.path+'/'+name)
class DB:
    def __init__(self):self.values={}
    def collection(self,name):return Collection(self,name)
    def transaction(self):return self
    def set(self,ref,value):self.values[ref.path]=copy.deepcopy(value)
    def update(self,ref,value):self.values[ref.path].update(copy.deepcopy(value))
class Data:
    def __init__(self):
        self.db=DB()
        self.couple={'members':['a','b'],'names':{'a':'Alex','b':'Sam'}}
        self.message={'kind':'court','senderId':'a','text':'Dishes'}
        self.db.values['closer_couples/c/messages/case1']=self.message
    def member(self,uid):
        if uid not in ('a','b'):raise AccessError(403,'Not paired')
        return 'c',self.couple

class SharedCourtTests(unittest.TestCase):
    def setUp(self):
        self.patch=patch('shared_court.firestore.transactional',lambda fn:fn);self.patch.start();self.addCleanup(self.patch.stop)
        self.data=Data()
    def ready(self):
        update(self.data,'a','case1',{'operation':'join'})
        state = update(self.data,'b','case1',{'operation':'join'})
        state.update(openingResponseDone=True, deadline=time.time()+120, aiConsent=['a','b'])
        self.data.db.values['closer_couples/c/hearings/case1'] = state
        self.data.db.values['closer_couples/c/hearing_calls/case1'] = {
            'status':'connected', 'offer':{'sdp':'offer'}, 'answer':{'sdp':'answer'},
            'readyAt':{'a':time.time(),'b':time.time()}}
        return state
    def test_both_partners_required_and_turn_roles_enforced(self):
        state=update(self.data,'a','case1',{'operation':'join'})
        with self.assertRaises(AccessError):update(self.data,'a','case1',{'operation':'turn','version':state['version'],'text':'Cook'})
        state=self.ready()
        with self.assertRaises(AccessError):update(self.data,'b','case1',{'operation':'turn','version':state['version'],'text':'Wrong role'})
        after=update(self.data,'a','case1',{'operation':'turn','version':state['version'],'text':'Cook dinner'})
        self.assertEqual(after['requestedRemedy'],'Cook dinner')
        with self.assertRaises(AccessError):update(self.data,'a','case1',{'operation':'turn','version':state['version'],'text':'stale'})
    def test_expiry_never_accepts_late_testimony(self):
        state=self.ready()
        self.data.db.values['closer_couples/c/hearings/case1']['deadline']=0
        after=update(self.data,'b','case1',{'operation':'turn','version':state['version'],'text':'Invented late answer'})
        self.assertIn('No answer',after['requestedRemedy'])
    def test_two_approvals_and_one_respondent_appeal(self):
        state=self.ready();state.update(phase=13,ruling={'proposedRemedy':'Share dishes'},model='muse-spark-1.3')
        self.data.db.values['closer_couples/c/hearings/case1']=state
        with self.assertRaises(AccessError):update(self.data,'a','case1',{'operation':'appeal','version':state['version']})
        accepted=update(self.data,'a','case1',{'operation':'accept','version':state['version']})
        self.assertEqual(accepted['phase'],13)
        closed=update(self.data,'b','case1',{'operation':'accept','version':accepted['version']})
        self.assertEqual(closed['closedStatus'],'accepted')
        self.assertEqual(self.data.message['kind'],'court')
    def test_outsider_and_unknown_case_blocked(self):
        with self.assertRaises(AccessError):update(self.data,'outsider','case1')
        with self.assertRaises(AccessError):update(self.data,'a','missing')

    def test_entering_screen_does_not_start_timer(self):
        update(self.data, 'a', 'case1', {'operation': 'join'})
        state = update(self.data, 'b', 'case1', {'operation': 'join'})
        self.assertIsNone(state['deadline'])
        with self.assertRaises(AccessError):
            update(self.data, 'a', 'case1', {'operation': 'turn', 'version':state['version'], 'text':'hello'})

    def test_stale_or_ended_call_blocks_turn(self):
        state = self.ready()
        call = self.data.db.values['closer_couples/c/hearing_calls/case1']
        call['readyAt']['b'] = 0
        with self.assertRaises(AccessError):
            update(self.data, 'a', 'case1', {'operation':'turn','version':state['version'],'text':'hello'})
        call['readyAt']['b'] = time.time()
        call['status'] = 'ended'
        with self.assertRaises(AccessError):
            update(self.data, 'a', 'case1', {'operation':'turn','version':state['version'],'text':'hello'})

    def test_end_identifies_partner_and_prevents_reentry(self):
        state = self.ready()
        ended = update(self.data, 'b', 'case1', {'operation':'end'})
        self.assertEqual(ended['endedByName'], 'Sam')
        with self.assertRaises(AccessError):
            update(self.data, 'a', 'case1', {'operation':'join'})
