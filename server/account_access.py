"""AI allowances bound to a verified account and its current pairing."""
import time
import re
from demo_security import AccessError, digest

class AccountAccess:
    def __init__(self, records, uid, couple_id, clock=time.time):
        self.records, self.uid, self.couple_id, self.clock = records, uid, couple_id, clock

    def reserve(self, token, operation, request_id, fingerprint):
        if operation not in {'hearing', 'characters', 'judge', 'segment'}:
            raise AccessError(400, 'Unknown AI operation.')
        if not isinstance(request_id, str) or not re.fullmatch('[A-Za-z0-9_-]{16,80}', request_id):
            raise AccessError(400, 'A valid request ID is required.')
        pair_key = 'account-pair:' + digest(self.couple_id)
        request_key = 'account-request:' + digest(self.uid + ':' + request_id)
        rate_key = 'account-rate:' + digest(self.uid)
        keys = ['policy', pair_key, request_key, rate_key]
        def update(state):
            now = self.clock()
            policy = state['policy']
            if not policy or not policy.get('enabled'):
                raise AccessError(503, 'Metherapy is temporarily unavailable.')
            if state[request_key] is not None:
                raise AccessError(409, 'This request was already submitted.')
            day, minute = int(now // 86400), int(now // 60)
            pair = state[pair_key] or {}
            count = pair.get('calls', 0) if pair.get('day') == day else 0
            rate = state[rate_key] or {}
            rate_count = rate.get('calls', 0) if rate.get('minute') == minute else 0
            if count >= 40 or rate_count >= 6:
                raise AccessError(429, 'Metherapy’s usage limit has been reached. Please try again later.')
            image = operation == 'characters'
            if policy['calls_used'] >= policy['calls_limit'] or (image and policy['images_used'] >= policy['images_limit']):
                raise AccessError(429, 'Metherapy’s service allowance has been reached. Please contact support.')
            leases = {key: expiry for key, expiry in policy.get('leases', {}).items() if expiry > now}
            if len(leases) >= 2:
                raise AccessError(429, 'Metherapy is busy. Please retry shortly.')
            leases[request_key] = now + 300
            policy.update(leases=leases, calls_used=policy['calls_used'] + 1)
            if image: policy['images_used'] += 1
            return {'request_key': request_key}, {
                'policy': policy, pair_key: {'day': day, 'calls': count + 1},
                rate_key: {'minute': minute, 'calls': rate_count + 1},
                request_key: {'created_at': now, 'fingerprint': fingerprint, 'operation': operation, 'status': 'reserved'}}
        return self.records.transaction(keys, update)

    def finish(self, reservation):
        key = reservation['request_key']
        def update(state):
            policy, request = state['policy'], state[key]
            changes = {}
            if policy:
                policy.get('leases', {}).pop(key, None)
                changes['policy'] = policy
            if request:
                request['status'] = 'finished'
                changes[key] = request
            return None, changes
        self.records.transaction(['policy', key], update)
