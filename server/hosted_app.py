"""Publicly reachable demo API with private, revocable judging access.

Run behind the hosting provider's HTTPS ingress. No Meta key or access code is
shipped in the app. Usage reservations are durable and occur before Meta calls.
"""
import hashlib
import json
import os
from contextlib import asynccontextmanager
from urllib.error import HTTPError, URLError
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool
from demo_security import AccessError, DemoAccess
from demo_storage import make_records
from judge_server import call_meta, validate
from court_protocol import call_hearing, validate_hearing
from sam_evidence import segment_evidence, validate_segment
from muse_image import create_scene, validate_photos

MODELS = {'muse-spark-1.3', 'muse-spark-1.2', 'muse-spark-1.1'}
LIMITS = {'judge': 32768, 'hearing': 6100000, 'characters': 3100000, 'segment': 1500000}


def reply(status, body):
    return JSONResponse(body, status_code=status, headers={
        'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
        **({'Retry-After': '60'} if status == 429 else {})})


async def read_json(request, limit):
    if request.headers.get('content-type', '').split(';')[0].strip().lower() != 'application/json':
        raise AccessError(415, 'Send JSON data.')
    if request.headers.get('content-encoding', 'identity').lower() != 'identity':
        raise AccessError(415, 'Compressed request bodies are not accepted.')
    declared = request.headers.get('content-length')
    if declared is not None:
        try:
            size = int(declared)
        except ValueError:
            raise AccessError(400, 'Invalid request size.')
        if size <= 0 or size > limit:
            raise AccessError(413, 'Request exceeds the upload limit.')
    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > limit:
            raise AccessError(413, 'Request exceeds the upload limit.')
    try:
        return json.loads(body)
    except (ValueError, UnicodeError):
        raise AccessError(400, 'Invalid JSON request.')


def make_app(records=None, api_key=None, model=None, clock=None):
    @asynccontextmanager
    async def lifespan(app):
        key = api_key if api_key is not None else os.environ.get('MODEL_API_KEY', '')
        selected = model or os.environ.get('META_JUDGE_MODEL', 'muse-spark-1.3')
        if not key or selected not in MODELS:
            raise RuntimeError('Configure MODEL_API_KEY and an allowed Meta judge model.')
        store = records if records is not None else make_records()
        security = DemoAccess(store, clock) if clock is not None else DemoAccess(store)
        if security.policy() is None:
            raise RuntimeError('Initialize the persistent demo policy before starting.')
        app.state.security, app.state.meta_key, app.state.meta_model = security, key, selected
        yield
    app = FastAPI(title='Closer demo backend', docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)

    @app.get('/healthz')
    def health():
        try:
            app.state.security.policy()
            return reply(200, {'status': 'ready'})
        except Exception:
            return reply(503, {'error': 'Service unavailable.'})

    @app.post('/auth/session')
    async def create_session(request: Request):
        try:
            body = await read_json(request, 1024)
            if not isinstance(body, dict) or set(body) != {'code'} or not isinstance(body['code'], str):
                raise AccessError(400, 'Enter your private demo code.')
            # Do not trust caller-supplied forwarded IP headers. This bucket may
            # group users behind a shared proxy; global and invite caps also apply.
            client = request.client.host if request.client else 'unknown'
            session = await run_in_threadpool(app.state.security.issue, body['code'], client)
            return reply(200, session)
        except AccessError as error:
            return reply(error.status, {'error': error.message})
        except Exception:
            return reply(503, {'error': 'Demo access is temporarily unavailable.'})

    @app.post('/judge')
    @app.post('/hearing')
    @app.post('/characters')
    @app.post('/segment')
    async def model_request(request: Request):
        reservation = None
        try:
            operation = request.url.path.rsplit('/', 1)[-1]
            header = request.headers.get('authorization', '')
            if not header.startswith('Bearer ') or len(header) > 160:
                raise AccessError(401, 'Enter your private demo code to connect.')
            token = header[7:]
            request_id = request.headers.get('x-request-id', '')
            payload = await read_json(request, LIMITS[operation])
            try:
                if operation == 'judge':
                    validate(payload)
                elif operation == 'hearing':
                    validate_hearing(payload)
                elif operation == 'segment':
                    validate_segment(payload)
                else:
                    validate_photos(payload)
            except (ValueError, KeyError, TypeError, UnicodeError):
                raise AccessError(400, 'The case data or image references are invalid.')
            fingerprint = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
            reservation = await run_in_threadpool(app.state.security.reserve, token, operation, request_id, fingerprint)
            # An operator can disable new calls immediately without redeploying.
            # Already-running provider requests may still complete.
            if operation == 'segment':
                result = await run_in_threadpool(segment_evidence, payload, app.state.meta_key)
            elif operation == 'characters':
                result = await run_in_threadpool(create_scene, payload, app.state.meta_key)
            elif operation == 'hearing':
                result = await run_in_threadpool(call_hearing, payload, app.state.meta_key, app.state.meta_model)
            else:
                result = await run_in_threadpool(call_meta, payload, app.state.meta_key, app.state.meta_model)
            return reply(200, result)
        except AccessError as error:
            return reply(error.status, {'error': error.message})
        except (HTTPError, URLError, TimeoutError, ValueError, TypeError, KeyError, OSError):
            return reply(502, {'error': 'Meta could not complete this request. You may retry within your demo allowance.'})
        except Exception:
            return reply(503, {'error': 'The demo cannot authorize this request right now.'})
        finally:
            if reservation is not None:
                try:
                    await run_in_threadpool(app.state.security.finish, reservation)
                except Exception:
                    # Fail closed: persistent counters stay charged and the
                    # in-flight lease expires after five minutes.
                    pass
    return app


app = make_app()
