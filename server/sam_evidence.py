"""Bounded SAM 3.1 object-box highlights; originals remain authoritative inputs."""
import json
import re
from urllib.request import Request, urlopen
from muse_image import validate_photos


def validate_segment(payload):
    if not isinstance(payload, dict) or set(payload) != {'image_base64', 'prompt'}:
        raise ValueError('Invalid segmentation request')
    prompt = payload['prompt']
    if not isinstance(prompt, str) or not 1 <= len(prompt.strip()) <= 80:
        raise ValueError('Name one object in 80 characters or fewer')
    image = validate_photos({'photos': [payload['image_base64']] * 2})[0]
    return image, prompt.strip()


def parse_boxes(text):
    if not text.strip():
        return []
    # Consume complete records; masks are deliberately not decoded or returned.
    record = re.compile(r'(\d+)<\|box;x1=(\d+);y1=(\d+);x2=(\d+);y2=(\d+);w=(\d+);h=(\d+)(?:;c=[0-9.]+)?\|><\|mask;[^\r\n]*?\|>')
    if not text.startswith('<0f>'):
        raise ValueError('Invalid SAM frame')
    remainder = text[4:].strip()
    boxes, ids, dimensions = [], set(), None
    while remainder:
        match = record.match(remainder)
        if not match or len(boxes) >= 50:
            raise ValueError('Invalid SAM record')
        oid, x1, y1, x2, y2, width, height = map(int, match.groups())
        if oid in ids or not (0 <= x1 < x2 <= width <= 20000 and 0 <= y1 < y2 <= height <= 20000):
            raise ValueError('Invalid SAM bounds')
        if dimensions is not None and dimensions != (width, height):
            raise ValueError('Inconsistent SAM dimensions')
        ids.add(oid)
        dimensions = (width, height)
        boxes.append({'id': oid, 'left': x1 / width, 'top': y1 / height,
                      'right': x2 / width, 'bottom': y2 / height})
        remainder = remainder[match.end():]
        if remainder:
            if not remainder.startswith(','):
                raise ValueError('Invalid SAM separator')
            remainder = remainder[1:]
            if not remainder:
                raise ValueError('Truncated SAM record')
    return boxes


def segment_evidence(payload, key):
    image, prompt = validate_segment(payload)
    body = {'model': 'sam-3.1', 'store': False, 'stream': True,
            'input': [{'role': 'user', 'content': [{'type': 'input_text', 'text': prompt},
                        {'type': 'input_image', 'image_url': image}]}]}
    request = Request('https://api.meta.ai/v1/responses', data=json.dumps(body).encode(),
                      headers={'Authorization': f'Bearer {key}', 'Content-Type': 'application/json',
                               'Accept': 'text/event-stream'}, method='POST')
    parts, count, completed = [], 0, False
    with urlopen(request, timeout=75) as response:
        while True:
            line = response.readline(2000001)
            if not line:
                break
            count += len(line)
            if count > 2000000:
                raise ValueError('SAM output exceeds limit')
            if not line.startswith(b'data:'):
                continue
            raw = line[5:].strip()
            if raw == b'[DONE]':
                break
            event = json.loads(raw)
            if event.get('type') == 'response.output_text.delta':
                delta = event.get('delta')
                if not isinstance(delta, str):
                    raise ValueError('Invalid SAM delta')
                parts.append(delta)
            elif event.get('type') == 'response.completed':
                if event.get('response', {}).get('status') != 'completed':
                    raise ValueError('Incomplete SAM result')
                completed = True
            elif event.get('type') in {'error', 'response.failed', 'response.incomplete'}:
                raise ValueError('SAM failed')
    if not completed:
        raise ValueError('Incomplete SAM stream')
    return {'model': 'sam-3.1', 'prompt': prompt, 'boxes': parse_boxes(''.join(parts))}
