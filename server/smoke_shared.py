"""Opt-in deployed shared-space smoke test. Creates then removes synthetic accounts/data."""
import base64
import os
import json
import secrets
import sys
import urllib.request
import urllib.error
from pathlib import Path
from google.cloud import firestore, storage

BASE='https://closer-demo-backend-97502564446.asia-southeast1.run.app'
PROJECT='iseeapp-ddf3a'
config=json.loads(Path('android/app/google-services.json').read_text())
client=next(c for c in config['client'] if c['client_info']['android_client_info']['package_name']=='com.jcm.closer')
KEY=client['api_key'][0]['current_key']
users=[];couple_id=None;photo_id=None;demo_token=None;demo_invite=None;security=None

def request(url,body=None,token=None,expected=200):
    raw=None if body is None else json.dumps(body).encode()
    headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})}
    if demo_token and url.startswith(BASE) and isinstance(body,dict) and body.get('operation')=='review':
        headers.update({'X-Demo-Session':demo_token,'X-Request-ID':secrets.token_urlsafe(18)})
    req=urllib.request.Request(url,data=raw,headers=headers)
    try:
        with urllib.request.urlopen(req,timeout=110) as response:
            data=response.read()
            return json.loads(data) if response.headers.get('Content-Type','').startswith('application/json') else data
    except urllib.error.HTTPError as e:
        if e.code==expected:return None
        # Never print credentials or entire auth responses.
        raise RuntimeError(f'HTTP {e.code} at '+url.split('?')[0]) from None

def act(index,body):return request(BASE+'/couple/action',body,users[index]['idToken'])

def court(index,cid,body=None):return request(BASE+'/couple/court/'+cid,body,users[index]['idToken'])

try:
    for index in range(3):
        user=request('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key='+KEY,{'email':'closer-smoke-'+secrets.token_hex(8)+'@example.com','password':secrets.token_urlsafe(24),'returnSecureToken':True})
        users.append(user)
        act(index,{'action':'profile','name':'Smoke '+str(index+1)})
    code=act(0,{'action':'invite'})['code']
    state=act(1,{'action':'join','code':code})
    couple_id=state['couple']['id']
    assert request(BASE+'/couple/state',token=users[0]['idToken'])['couple']['id']==couple_id
    print('PASS: separate Firebase accounts pair into one shared space')
    message_id='smoke_'+secrets.token_hex(8)
    act(0,{'action':'message','id':message_id,'text':'Shared real message'})
    assert any(m['id']==message_id for m in request(BASE+'/couple/state',token=users[1]['idToken'])['messages'])
    act(1,{'action':'heart','id':message_id,'liked':True})
    print('PASS: cross-account message delivery and reaction')
    png=base64.b64encode(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVwAAAABJRU5ErkJggg==')).decode()
    photo_id=request(BASE+'/couple/photo',{'image_base64':png},users[0]['idToken'])['id']
    original=request(BASE+'/couple/photo/'+photo_id,token=users[1]['idToken'])
    assert original==base64.b64decode(png)
    request(BASE+'/couple/photo/'+photo_id,token=users[2]['idToken'],expected=409)
    act(0,{'action':'memory','id':'memory_'+secrets.token_hex(8),'text':'Test memory','photoId':photo_id})
    assert request(BASE+'/couple/state',token=users[1]['idToken'])['memories']
    print('PASS: shared private photo and memory; unrelated account blocked')
    act(0,{'action':'location','location':{'lat':1.3521,'lon':103.8198}})
    assert users[0]['localId'] in request(BASE+'/couple/state',token=users[1]['idToken'])['couple']['locations']
    act(0,{'action':'location','location':None})
    assert users[0]['localId'] not in request(BASE+'/couple/state',token=users[1]['idToken'])['couple']['locations']
    print('PASS: opt-in location sharing and removal')
    case_id='court_'+secrets.token_hex(8)
    act(0,{'action':'message','id':case_id,'text':'Fictional dishes case','summons':True})
    first=court(0,case_id,{'operation':'join'})
    second=court(1,case_id,{'operation':'join'})
    request(BASE+'/couple/court/'+case_id,{'operation':'turn','version':second['version'],'text':'Not my turn'},users[1]['idToken'],expected=403)
    next_state=court(0,case_id,{'operation':'turn','version':second['version'],'text':'Cook once'})
    assert next_state['phase']==1 and next_state['requestedRemedy']=='Cook once'
    request(BASE+'/couple/court/'+case_id,{'operation':'turn','version':second['version'],'text':'stale'},users[0]['idToken'],expected=409)
    request(BASE+'/couple/court/'+case_id,token=users[2]['idToken'],expected=409)
    print('PASS: shared hearing join, role enforcement, stale-write protection and isolation')
    if '--ai' in sys.argv:
        from demo_security import DemoAccess
        from demo_storage import make_records
        from shared_court import TURNS
        os.environ.update(BUDGET_STORE='firestore', GOOGLE_CLOUD_PROJECT=PROJECT, FIRESTORE_DATABASE='closer-demo-backend')
        security=DemoAccess(make_records())
        demo_invite=security.create_invite('Temporary shared-hearing live test',3,0,1,1)
        demo_token=request(BASE+'/auth/session',{'code':demo_invite['code']})['session_token']
        state=court(0,case_id)
        while state['phase'] < 9:
            role=TURNS[state['phase']][0]
            state=court(role,case_id,{'operation':'turn','version':state['version'],'text':'Fictional test: both people agree to share cleanup fairly.'})
        state=court(0,case_id,{'operation':'review','version':state['version']})
        assert state['model']=='muse-spark-1.3' and state['phase']==10
        for role in [0,1]:state=court(role,case_id,{'operation':'turn','version':state['version'],'text':'A shared cleanup is practical and voluntary.'})
        state=court(0,case_id,{'operation':'review','version':state['version']})
        assert state['phase']==13 and state['ruling']['requestedRemedy']=='Cook once'
        state=court(1,case_id,{'operation':'appeal','version':state['version']})
        state=court(1,case_id,{'operation':'turn','version':state['version'],'text':'Please consider splitting cleanup instead.'})
        state=court(0,case_id,{'operation':'turn','version':state['version'],'text':'I agree to discuss splitting cleanup.'})
        state=court(1,case_id,{'operation':'review','version':state['version']})
        assert state['model']=='muse-wonder-1.0' and state['phase']==17
        for role in [0,1]:state=court(role,case_id,{'operation':'accept','version':state['version']})
        assert state['phase']==18 and state['closedStatus']=='accepted'
        print('PASS: actual Spark questions/verdict, Wonder appeal and separate partner approvals')

finally:
    if security is not None and demo_invite is not None:security.revoke(demo_invite['id'])
    db=firestore.Client(project=PROJECT,database='closer-demo-backend')
    if couple_id:
        root=db.collection('closer_couples').document(couple_id)
        state=root.get().to_dict() or {}
        assert set(state.get('members',[]))=={u['localId'] for u in users[:2]}
        for col in root.collections():
            for doc in col.stream():doc.reference.delete()
        root.delete()
        if photo_id:storage.Client(project=PROJECT).bucket(PROJECT+'-closer-media').blob(couple_id+'/'+photo_id).delete()
    for user in users:
        uid=user['localId']
        for collection in ['closer_profiles','closer_app_limits']:
            db.collection(collection).document(uid).delete()
        for invite in db.collection('closer_pair_invites').where(filter=firestore.FieldFilter('owner','==',uid)).stream():invite.reference.delete()
        request('https://identitytoolkit.googleapis.com/v1/accounts:delete?key='+KEY,{'idToken':user['idToken']})
    print('Synthetic test accounts and data removed')
