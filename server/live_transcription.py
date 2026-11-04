"""Authenticated, bounded PCM relay. Audio is transient and never written to disk."""
import asyncio
import json
import time
import uuid
from contextlib import suppress
from fastapi import WebSocketDisconnect
from google.cloud import firestore
from starlette.concurrency import run_in_threadpool
from websockets.asyncio.client import connect
from account_access import AccountAccess
from demo_security import AccessError
from shared_court import ref_for, require_live_call, TURNS, update

LANGUAGES = {'en':'English','id':'Indonesian','ms':'Malay','hi':'Hindi','fil':'Tagalog'}

def admit_stream(data, uid, case_id, version, stream_id):
    root, ref, _, _ = ref_for(data, uid, case_id)
    @firestore.transactional
    def reserve(tx):
        state = ref.get(transaction=tx).to_dict() or {}
        require_live_call(root, case_id, state.get('people', []), tx)
        call = root.collection('hearing_calls').document(case_id).get(transaction=tx).to_dict() or {}
        if set(call.get('audioConsent', [])) != set(state.get('people', [])):
            raise AccessError(403, 'Both partners must join with audio-processing consent.')
        phase = state.get('phase')
        role = TURNS.get(phase, (None,))[0]
        if (phase not in TURNS or state['people'][role] != uid or state.get('version') != version
                or not state.get('openingResponseDone') or state.get('facilitatorPending')
                or state.get('playbackPending') or not state.get('deadline') or state['deadline'] <= time.time()):
            raise AccessError(409, 'Wait for your connected speaking turn.')
        lease = state.get('audioLease') or {}
        if lease.get('until',0) > time.time():
            raise AccessError(409, 'This turn already has an audio stream.')
        tx.update(ref, {'audioLease':{'id':stream_id,'until':time.time()+150}})
        return root.id, state
    return reserve(data.db.transaction())

def release_stream(data, uid, case_id, stream_id):
    _, ref, _, _ = ref_for(data, uid, case_id)
    @firestore.transactional
    def release(tx):
        state = ref.get(transaction=tx).to_dict() or {}
        if (state.get('audioLease') or {}).get('id') == stream_id:
            tx.update(ref, {'audioLease':None})
    release(data.db.transaction())

def validate_pcm(frame, total):
    if not frame or len(frame) > 6400 or len(frame) % 2 or total + len(frame) > 4_000_000:
        raise AccessError(413, 'Invalid or oversized audio frame.')

async def relay(ws, data_factory, api_key, records, case_id):
    await ws.accept()
    data = uid = reservation = access = None
    stream_id = uuid.uuid4().hex
    tasks = []
    try:
        hello = json.loads(await asyncio.wait_for(ws.receive_text(), 10))
        token = hello.get('token','')
        if not isinstance(token,str) or not 1 <= len(token) <= 8192 or type(hello.get('version')) is not int:
            raise AccessError(401, 'Sign in and join your speaking turn.')
        data = data_factory()
        uid = await run_in_threadpool(data.user, token)
        cid, state = await run_in_threadpool(admit_stream, data, uid, case_id, hello['version'], stream_id)
        access = AccountAccess(records, uid, cid)
        reservation = await run_in_threadpool(access.reserve, '', 'hearing', stream_id, 'voice:'+case_id+':'+str(hello['version']))
        async with connect('wss://api.meta.ai/v1/asr/realtime', open_timeout=15, max_size=65536, max_queue=16) as upstream:
            await upstream.send(json.dumps({'authorization':{'accessToken':'Bearer '+api_key},
                'audioEncoding':'PCM_16KHZ','model':'muse-voice-transcribe-1.0',
                'mode':'ENDPOINTING','partialMode':'CUMULATIVE',
                'languageBias':[LANGUAGES.get(state.get('therapyLanguage'),'English')]}))
            ack = json.loads(await asyncio.wait_for(upstream.recv(), 15))
            if 'sessionId' not in ack:
                raise AccessError(503, 'Meta voice transcription is unavailable for this account.')
            await ws.send_json({'type':'ready'})
            completed = {}
            started = time.monotonic()
            total = 0
            ending = asyncio.Event()

            async def audio_in():
                nonlocal total
                while True:
                    frame = await ws.receive()
                    if frame['type'] == 'websocket.disconnect':
                        raise WebSocketDisconnect()
                    if frame.get('bytes') is not None:
                        pcm = frame['bytes']
                        validate_pcm(pcm,total)
                        total += len(pcm)
                        if total > (time.monotonic()-started+2)*32000:
                            raise AccessError(429, 'Send audio at microphone speed.')
                        await upstream.send(pcm)
                    elif frame.get('text'):
                        event = json.loads(frame['text'])
                        if event.get('type') != 'endStream':
                            raise AccessError(400,'Invalid audio control message.')
                        ending.set()
                        await upstream.send('{"type":"endStream"}')
                        return

            async def text_out():
                async for raw in upstream:
                    if not isinstance(raw,str): continue
                    event = json.loads(raw)
                    kind = event.get('type')
                    if kind == 'error':
                        raise AccessError(503,'Meta could not transcribe this turn. Please try again.')
                    if kind == 'speechComplete':
                        text = event.get('transcript','')
                        if isinstance(text,str): completed[event.get('turnId',len(completed))] = text[:2000]
                    if kind in {'speechStart','speechEnd','speechComplete','transcript'}:
                        await ws.send_json({key:event[key] for key in ('type','turnId','transcript','final') if key in event})
                if not ending.is_set():
                    raise AccessError(503,'Transcription disconnected. Your turn was not submitted.')

            async def monitor():
                while True:
                    await asyncio.sleep(4)
                    root, ref, _, _ = await run_in_threadpool(ref_for,data,uid,case_id)
                    current = await run_in_threadpool(lambda: ref.get().to_dict() or {})
                    await run_in_threadpool(require_live_call,root,case_id,current.get('people',[]))
                    if current.get('version') != hello['version'] or current.get('phase') == 18:
                        raise AccessError(409,'The session changed. Audio capture stopped.')

            tasks = [asyncio.create_task(audio_in()),asyncio.create_task(text_out()),asyncio.create_task(monitor())]
            async def collect():
                pending = set(tasks)
                while tasks[1] in pending:
                    done,pending = await asyncio.wait(pending,return_when=asyncio.FIRST_COMPLETED)
                    for task in done: task.result()
                return ' '.join(completed.values()).strip()
            transcript = await asyncio.wait_for(collect(), min(140, max(5,state['deadline']-time.time()+15)))
            if not transcript:
                await ws.send_json({'type':'empty','message':'No speech detected. Your turn has not been submitted.'})
                return
            if len(transcript)>2000:
                raise AccessError(400,'That turn was too long. Please use a shorter spoken response.')
            result = await run_in_threadpool(update,data,uid,case_id,
                {'operation':'turn','version':hello['version'],'text':transcript}, hello['version'])
            await ws.send_json({'type':'submitted','transcript':transcript,'state':result})
    except WebSocketDisconnect:
        pass
    except AccessError as error:
        with suppress(Exception): await ws.send_json({'type':'error','message':error.message})
    except Exception:
        with suppress(Exception): await ws.send_json({'type':'error','message':'Live transcription stopped. Reconnect or type your turn; nothing was submitted.'})
    finally:
        for task in tasks: task.cancel()
        if tasks: await asyncio.gather(*tasks,return_exceptions=True)
        if reservation:
            with suppress(Exception): await run_in_threadpool(access.finish,reservation)
        if data and uid:
            with suppress(Exception): await run_in_threadpool(release_stream,data,uid,case_id,stream_id)
        with suppress(Exception): await ws.close()
