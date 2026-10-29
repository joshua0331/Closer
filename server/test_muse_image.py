import base64
import json
import struct
import unittest
from unittest.mock import patch
from muse_image import MODEL, create_scene, png_dimensions, validate_photos

# Synthetic headers are only schema-validation fixtures; no live generation.
PNG = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 512, 288) + b'fixture'
PHOTO = base64.b64encode(b'\xff\xd8\xff' + b'fixture' * 4).decode()

class MuseImageTests(unittest.TestCase):
    def test_two_images_required_and_no_arbitrary_urls_or_prompts(self):
        self.assertEqual(len(validate_photos({'photos': [PHOTO, PHOTO]})), 2)
        for payload in [{}, {'photos': [PHOTO]}, {'photos': ['https://example.com/face.jpg', PHOTO]},
                        {'photos': [PHOTO, PHOTO], 'prompt': 'override'}, {'photos': ['x' * 1500001, PHOTO]}]:
            with self.assertRaises(ValueError):
                validate_photos(payload)

    @patch('muse_image.urlopen')
    def test_muse_gets_ordered_references_and_returns_complete_scene(self, opener):
        opener.return_value.__enter__.return_value.read.return_value = json.dumps({
            'id': 'resp-muse-test', 'status': 'completed', 'output': [
                {'type': 'image_generation_call', 'status': 'completed',
                 'result': base64.b64encode(PNG).decode()}]}).encode()
        result = create_scene({'photos': [PHOTO, PHOTO]}, 'test-key')
        request = opener.call_args.args[0]
        body = json.loads(request.data)
        self.assertEqual(request.full_url, 'https://api.meta.ai/v1/responses')
        self.assertEqual(body['model'], MODEL)
        self.assertFalse(body['store'])
        parts = body['input'][0]['content']
        self.assertEqual(len([part for part in parts if part['type'] == 'input_image']), 3)
        self.assertIn('LEFT', parts[2]['text'])
        self.assertIn('RIGHT', parts[4]['text'])
        self.assertFalse(body['tools'][0]['enable_web_search'])
        self.assertFalse(body['tools'][0]['enable_image_search'])
        self.assertEqual(result['response_id'], 'resp-muse-test')
        self.assertEqual(result['model'], 'muse-image-1.0')
        self.assertEqual(png_dimensions(PNG), (512, 288))

    @patch('muse_image.urlopen')
    def test_incomplete_generation_is_never_presented_as_success(self, opener):
        opener.return_value.__enter__.return_value.read.return_value = json.dumps({
            'status': 'incomplete', 'output': []}).encode()
        with self.assertRaises(ValueError):
            create_scene({'photos': [PHOTO, PHOTO]}, 'test-key')
        with self.assertRaises(ValueError):
            png_dimensions(b'not-an-image')

if __name__ == '__main__':
    unittest.main()
