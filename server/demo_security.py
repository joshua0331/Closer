"""Invite-only demo sessions and durable, pre-charged request quotas."""
import hashlib
import re
import secrets
import time
from datetime import datetime, timezone


class AccessError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message
        super().__init__(message)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class DemoAccess:
    def __init__(self, records, clock=time.time):
        self.records, self.clock = records, clock

    def initialize(self, calls=100, images=5, hours=336):
        if not 1 <= calls <= 1000 or not 0 <= images <= calls or not 1 <= hours <= 720:
            raise ValueError('Invalid demo limits')
        def update(state):
            if state['policy'] is not None:
                raise ValueError('Demo already initialized; counters were not reset.')
            policy = {'enabled': True, 'ends_at': self.clock() + hours * 3600,
                      'calls_limit': calls, 'images_limit': images,
                      'calls_used': 0, 'images_used': 0, 'leases': {}}
            return policy, {'policy': policy}
        return self.records.transaction(['policy'], update)

    def policy(self):
        return self.records.transaction(['policy'], lambda state: (state['policy'], {}))

    def set_enabled(self, enabled):
        def update(state):
            policy = state['policy']
            if policy is None:
                raise ValueError('Initialize the demo first')
            policy['enabled'] = bool(enabled)
            return None, {'policy': policy}
        self.records.transaction(['policy'], update)

    def create_invite(self, label, calls=20, images=1, hours=336, sessions=6):
        if not label.strip() or len(label) > 80 or not 1 <= calls <= 1000 or not 0 <= images <= calls or not 1 <= sessions <= 10 or not 1 <= hours <= 720:
            raise ValueError('Invalid invite limits')
        code = secrets.token_urlsafe(24)
        invite_id = digest(code)
        key = 'invite:' + invite_id
        def update(state):
            policy = self._check_policy(state['policy'])
            invite = {'label': label.strip(), 'enabled': True, 'expires_at': min(self.clock() + hours * 3600, policy['ends_at']),
                      'calls_limit': calls, 'images_limit': images, 'calls_used': 0, 'images_used': 0,
                      'sessions_limit': sessions, 'sessions_issued': 0}
            return {'id': invite_id, 'code': code, 'expires_at': invite['expires_at']}, {key: invite}
        return self.records.transaction(['policy', key], update)

    def revoke(self, invite_id):
        if not re.fullmatch('[a-f0-9]{64}', invite_id):
            raise ValueError('Invalid invite ID')
        key = 'invite:' + invite_id
        def update(state):
            if state[key] is None:
                raise ValueError('Unknown invite')
            invite = state[key]
            invite['enabled'] = False
            return None, {key: invite}
        self.records.transaction([key], update)

    def _check_policy(self, policy):
        if policy is None or not policy.get('enabled') or policy.get('ends_at', 0) <= self.clock():
            raise AccessError(503, 'The AI demo is currently unavailable.')
        return policy

    def _auth_rate(self, client):
        minute = int(self.clock() // 60)
        keys = ['auth:global', 'auth:ip:' + digest(client)]
        def update(state):
            changes = {}
            for key, maximum in [(keys[0], 30), (keys[1], 10)]:
                value = state[key] or {}
                count = value.get('count', 0) if value.get('minute') == minute else 0
                if count >= maximum:
                    raise AccessError(429, 'Too many access attempts. Please wait a minute.')
                changes[key] = {'minute': minute, 'count': count + 1}
            return None, changes
        self.records.transaction(keys, update)

    def issue(self, code, client='local'):
        self._auth_rate(client)
        if not isinstance(code, str) or not re.fullmatch('[A-Za-z0-9_-]{32,128}', code):
            raise AccessError(401, 'The demo code is invalid or unavailable.')
        invite_id = digest(code)
        key = 'invite:' + invite_id
        token = secrets.token_urlsafe(32)
        session_key = 'session:' + digest(token)
        def update(state):
            policy = self._check_policy(state['policy'])
            invite = state[key]
            if not invite or not invite['enabled'] or invite['expires_at'] <= self.clock():
                raise AccessError(401, 'The demo code is invalid or unavailable.')
            if invite['sessions_issued'] >= invite['sessions_limit']:
                raise AccessError(403, 'This demo code has no sessions left. Request a new code from the demo owner.')
            invite['sessions_issued'] += 1
            expires = min(self.clock() + 8 * 3600, invite['expires_at'], policy['ends_at'])
            session = {'invite': invite_id, 'expires_at': expires, 'inflight': None}
            return {'session_token': token, 'expires_at': expires}, {key: invite, session_key: session}
        return self.records.transaction(['policy', key, session_key], update)

    def reserve(self, token, operation, request_id, fingerprint):
        if operation not in {'judge', 'hearing', 'characters', 'segment'}:
            raise AccessError(404, 'Unknown operation')
        if not isinstance(token, str) or not re.fullmatch('[A-Za-z0-9_-]{32,128}', token):
            raise AccessError(401, 'Enter your private demo code to connect.')
        if not isinstance(request_id, str) or not re.fullmatch('[A-Za-z0-9_-]{16,80}', request_id):
            raise AccessError(400, 'A valid request ID is required.')
        session_key = 'session:' + digest(token)
        # The session's invite pointer cannot be changed by app clients.
        session = self.records.transaction([session_key], lambda state: (state[session_key], {}))
        if not session:
            raise AccessError(401, 'Your demo session has expired. Enter the code again.')
        invite_key = 'invite:' + session['invite']
        request_key = 'request:' + digest(token + ':' + request_id)
        keys = ['policy', session_key, invite_key, request_key, 'calls:minute']
        def update(state):
            now = self.clock()
            policy = self._check_policy(state['policy'])
            active = state[session_key]
            invite = state[invite_key]
            if not active or active['expires_at'] <= now or not invite or not invite['enabled'] or invite['expires_at'] <= now:
                raise AccessError(401, 'Your demo session is no longer available.')
            if state[request_key] is not None:
                raise AccessError(409, 'This request was already submitted. No second AI call was made.')
            inflight = active.get('inflight')
            if inflight and inflight['until'] > now:
                raise AccessError(409, 'Wait for your current AI request to finish.')
            minute = int(now // 60)
            rate = state['calls:minute'] or {}
            count = rate.get('count', 0) if rate.get('minute') == minute else 0
            if count >= 12:
                raise AccessError(429, 'The demo is busy. Please wait a minute.')
            image = operation == 'characters'
            for budget in (policy, invite):
                if budget['calls_used'] >= budget['calls_limit'] or (image and budget['images_used'] >= budget['images_limit']):
                    raise AccessError(429, 'The demo usage allowance has been reached. Contact the demo owner.')
            leases = {key: expiry for key, expiry in policy.get('leases', {}).items() if expiry > now}
            if len(leases) >= 2:
                raise AccessError(429, 'The demo is busy. Please try again shortly.')
            leases[request_key] = now + 300
            policy['leases'] = leases
            for budget in (policy, invite):
                budget['calls_used'] += 1
                if image:
                    budget['images_used'] += 1
            active['inflight'] = {'request': request_key, 'until': now + 300}
            request = {'status': 'reserved', 'operation': operation, 'fingerprint': fingerprint, 'created_at': now}
            changes = {'policy': policy, invite_key: invite, session_key: active, request_key: request,
                       'calls:minute': {'minute': minute, 'count': count + 1}}
            return {'session_key': session_key, 'request_key': request_key}, changes
        return self.records.transaction(keys, update)

    def finish(self, reservation):
        session_key, request_key = reservation['session_key'], reservation['request_key']
        def update(state):
            changes = {}
            policy = state['policy']
            if policy:
                policy.get('leases', {}).pop(request_key, None)
                changes['policy'] = policy
            session = state[session_key]
            if session and (session.get('inflight') or {}).get('request') == request_key:
                session['inflight'] = None
                changes[session_key] = session
            request = state[request_key]
            if request:
                request['status'] = 'finished'
                changes[request_key] = request
            return None, changes
        self.records.transaction(['policy', session_key, request_key], update)
