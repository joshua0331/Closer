"""Opt-in live guest-room test using synthetic data; no accounts or credentials printed."""
import base64
import hashlib
import json
import os
import secrets
import struct
import sys
import zlib
from concurrent.futures import ThreadPoolExecutor
import requests
from google.cloud import firestore, storage

BASE = 'https://closer-demo-backend-97502564446.asia-southeast1.run.app'
PROJECT = 'iseeapp-ddf3a'
rooms = []; sessions = []; ai_sessions = []
def chunk(kind, raw): return struct.pack('>I', len(raw)) + kind + raw + struct.pack('>I', zlib.crc32(kind + raw) & 0xffffffff)
raw = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',128,128,8,2,0,0,0)) + chunk(b'IDAT', zlib.compress((b'\x00' + bytes([255,220,200])*128)*128)) + chunk(b'IEND', b'')
image = base64.b64encode(raw).decode()
def call(path, body=None, session=None, ai=None, expected=200):
    headers = {'Origin': 'https://closer-court-ddf3a.web.app'}
    if session: headers['Authorization'] = 'Bearer ' + session['session']
    if ai: headers.update({'X-Demo-Session': ai['session_token'], 'X-Request-ID': secrets.token_urlsafe(18)})
    response = requests.request('GET' if body is None else 'POST', BASE+path, headers=headers, json=body, timeout=120)
    assert response.status_code == expected, f'{path}: HTTP {response.status_code}: {response.json().get("error", "unexpected response")}'
    return response.json()
def state(index, body=None): return call('/couple/court/hearing', body, sessions[index], ai_sessions[index] if ai_sessions else None)
try:
    host = call('/rooms/create', {'name': 'Synthetic host', 'topic': 'Fictional test: sharing dish cleanup', 'image_base64': image, 'consent': True})
    rooms.append(host); sessions.append(host)
    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(lambda i: requests.post(BASE+'/rooms/join', json={'name': 'Synthetic guest '+str(i), 'code': host['invite'], 'image_base64': image, 'consent': True}, timeout=60), range(2)))
    assert sorted(r.status_code for r in outcomes) == [200,409]
    guest = next(r.json() for r in outcomes if r.status_code == 200); sessions.append(guest)
    print('PASS: no-account room creation and atomic two-seat invitation claim')
    for session in sessions:
        ai = call('/rooms/ai-session', {}, session); ai_sessions.append(ai)
    print('PASS: automatic private room AI sessions, without a demo code')
    room = call('/couple/state', session=guest)
    assert len(room['couple']['members']) == 2
    assert room['couple']['names'][host['uid']] == 'Synthetic host'
    call('/couple/state', session={'session': 'room_' + secrets.token_urlsafe(32)}, expected=401)
    call('/couple/action', {'action': 'invite'}, host, expected=403)
    call('/couple/action', {'action': 'message', 'id': 'smoke_'+secrets.token_hex(8), 'text': 'Can we share cleanup?'}, host)
    assert any(m.get('text') == 'Can we share cleanup?' for m in call('/couple/state', session=guest)['messages'])
    print('PASS: private room membership and synchronized chat')
    hearing = state(0)
    assert all(hearing['portraits']) and len(hearing['names']) == 2
    for portrait in hearing['portraits']:
        response=requests.get(BASE+'/couple/photo/'+portrait, headers={'Authorization': 'Bearer '+guest['session']}, timeout=30)
        assert response.status_code==200 and response.content==raw
    photo = call('/couple/photo', {'image_base64': image}, host)['id']
    hearing = state(0, {'operation':'evidence', 'version':hearing['version'], 'photoId':photo, 'caption':'Synthetic solid-color test card; does not prove the dispute.'})
    assert len(hearing['evidence']) == 1 and not hearing['joined']
    state(0, {'operation':'join'}); hearing = state(1, {'operation':'join'})
    assert len(hearing['joined'])==2 and hearing['deadline']
    call('/couple/court/hearing', {'operation':'turn','version':hearing['version'],'text':'Wrong role'}, guest, expected=403)
    print('PASS: two selfies, shared evidence before hearing, both-person start and timed role lock')
    if '--ai' in sys.argv:
        from shared_court import TURNS
        while hearing['phase'] < 9:
            role = TURNS[hearing['phase']][0]
            hearing = state(role, {'operation':'turn','version':hearing['version'], 'text':'Share the dishes cleanup voluntarily. This is a fictional integration test; the color card proves nothing.'})
        hearing = state(0, {'operation':'review','version':hearing['version']})
        assert hearing['phase']==10 and hearing['model']=='muse-spark-1.3'
        for role in [0,1]: hearing=state(role, {'operation':'turn','version':hearing['version'],'text':'We both agree to a practical shared cleanup, with no forced compensation.'})
        hearing=state(0, {'operation':'review','version':hearing['version']})
        assert hearing['phase']==13
        hearing=state(1, {'operation':'appeal','version':hearing['version']})
        for role in [1,0]: hearing=state(role, {'operation':'turn','version':hearing['version'],'text':'Consider alternating dishes cleanup rather than doing it together.'})
        hearing=state(1, {'operation':'review','version':hearing['version']})
        assert hearing['phase']==17 and hearing['model']=='muse-wonder-1.0'
        for role in [0,1]: hearing=state(role, {'operation':'accept','version':hearing['version']})
        assert hearing['phase']==18 and hearing['closedStatus']=='accepted'
        print('PASS: live Spark evidence/questions/ruling, Wonder appeal and both guest approvals')
finally:
    db=firestore.Client(project=PROJECT,database='closer-demo-backend')
    bucket=storage.Client(project=PROJECT).bucket(PROJECT+'-closer-media')
    for host in rooms:
        root=db.collection('closer_couples').document(host['roomId'])
        record=root.get().to_dict() or {}
        for uid in record.get('members',[]):
            db.collection('closer_profiles').document(uid).delete()
            db.collection('closer_app_limits').document(uid).delete()
        for collection in root.collections():
            for doc in collection.stream(): doc.reference.delete()
        for blob in bucket.list_blobs(prefix=host['roomId']+'/'): blob.delete()
        root.delete()
        db.collection('court_room_invites').document(hashlib.sha256(host['invite'].encode()).hexdigest()).delete()
        # Revoke only the synthetic room's AI grant; preserve global usage counters.
        os.environ.update(GOOGLE_CLOUD_PROJECT=PROJECT,FIRESTORE_DATABASE='closer-demo-backend',BUDGET_STORE='firestore')
        from demo_security import DemoAccess
        from demo_storage import make_records
        DemoAccess(make_records()).revoke(hashlib.sha256(('court-room:'+host['roomId']).encode()).hexdigest())
    for session in sessions:
        db.collection('court_room_sessions').document(hashlib.sha256(session['session'].encode()).hexdigest()).delete()
    print('Synthetic guest room data removed; global AI counters preserved.')
