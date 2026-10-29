"""Muse Image scene generation. Photos are inputs to the model, never UI overlays."""
import base64
import binascii
import json
import struct
from pathlib import Path
from urllib.request import Request, urlopen

MODEL = 'muse-image-1.0'
PROMPT_VERSION = 'couple-court-scene-v1'
PROMPT = '''Create one cohesive original pixel-art Couple Court scene in a wide
16:9 composition. Image 1 is the courtroom layout and style reference ONLY.
Image 2 is the identity reference for the LEFT participant; image 3 is the
identity reference for the RIGHT participant. Redraw BOTH people as pixel-art
characters with recognizable facial features, hair and skin tones from their
respective reference photos. Use each reference only for its assigned person.
Integrate their faces naturally into their heads and bodies in matching pixel
scale, lighting, palette and perspective. Do not paste photographs, use circular
photo badges, make face cutouts, or create photorealistic faces. Preserve the
friendly judge with visible face at the central raised bench, wood courtroom,
golden sconces, doors, opposing podiums and comfortable empty space. Keep left
participant in a peach casual shirt and right participant in a teal casual shirt;
adapt the characters naturally to each supplied adult reference. Both participant
faces and the judge must be clearly visible. Match the reference's crisp square
pixel clusters, warm detailed wood textures, expressive adventure-game character
proportions and cozy light. Do not add text, logos, overlays, UI or extra people.
Do not infer personality, health, guilt or relationship quality from appearance.
Return the full finished scene, not individual face sprites.'''


def png_dimensions(raw):
    if len(raw) < 24 or raw[:8] != b'\x89PNG\r\n\x1a\n' or raw[12:16] != b'IHDR':
        raise ValueError('Expected PNG artwork')
    width, height = struct.unpack('>II', raw[16:24])
    if not (64 <= width <= 8192 and 64 <= height <= 8192 and width * height <= 20000000):
        raise ValueError('Invalid artwork dimensions')
    return width, height


def validate_photos(payload):
    if not isinstance(payload, dict) or set(payload) != {'photos'}:
        raise ValueError('Expected two photo references')
    photos = payload['photos']
    if not isinstance(photos, list) or len(photos) != 2:
        raise ValueError('Two photos are required')
    normalized = []
    for encoded in photos:
        if not isinstance(encoded, str) or len(encoded) > 1500000:
            raise ValueError('Photo exceeds limit')
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (ValueError, binascii.Error) as error:
            raise ValueError('Invalid photo') from error
        if not 20 <= len(raw) <= 1000000:
            raise ValueError('Invalid photo size')
        if raw.startswith(b'\x89PNG\r\n\x1a\n'):
            mime = 'image/png'
        elif raw.startswith(b'\xff\xd8\xff'):
            mime = 'image/jpeg'
        else:
            raise ValueError('Use PNG or JPEG photos')
        normalized.append(f'data:{mime};base64,{encoded}')
    return normalized


def create_scene(payload, key):
    photos = validate_photos(payload)
    reference = Path(__file__).resolve().parent.parent / 'assets' / 'court' / 'courtroom.png'
    reference_url = 'data:image/png;base64,' + base64.b64encode(reference.read_bytes()).decode()
    content = [{'type': 'input_text', 'text': PROMPT},
               {'type': 'input_image', 'image_url': reference_url},
               {'type': 'input_text', 'text': 'LEFT participant identity reference:'},
               {'type': 'input_image', 'image_url': photos[0]},
               {'type': 'input_text', 'text': 'RIGHT participant identity reference:'},
               {'type': 'input_image', 'image_url': photos[1]}]
    body = {'model': MODEL, 'store': False,
            'input': [{'role': 'user', 'content': content}],
            'tools': [{'type': 'image_generation', 'output_format': 'png',
                       'size': '1792x1024', 'reasoning_strength': 'high',
                       'enable_image_search': False, 'enable_web_search': False,
                       'enable_shell': False}]}
    request = Request('https://api.meta.ai/v1/responses', data=json.dumps(body).encode(),
                      headers={'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'}, method='POST')
    with urlopen(request, timeout=180) as response:
        raw_response = response.read(20000001)
    if len(raw_response) > 20000000:
        raise ValueError('Artwork response exceeds limit')
    result = json.loads(raw_response)
    if result.get('status') != 'completed':
        raise ValueError('Artwork was not completed')
    images = [item for item in result.get('output', [])
              if item.get('type') == 'image_generation_call' and item.get('status') == 'completed']
    if len(images) != 1 or not isinstance(images[0].get('result'), str):
        raise ValueError('No completed artwork')
    encoded = images[0]['result']
    image = base64.b64decode(encoded, validate=True)
    if len(image) > 12000000:
        raise ValueError('Artwork exceeds limit')
    width, height = png_dimensions(image)
    return {'image_base64': encoded, 'model': MODEL, 'response_id': result.get('id', ''),
            'prompt_version': PROMPT_VERSION, 'width': width, 'height': height}
