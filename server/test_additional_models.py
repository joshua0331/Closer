import json
import unittest
from unittest.mock import patch
from sam_evidence import parse_boxes, segment_evidence, validate_segment
from test_court_protocol import PHOTO, CASE, RULING
from court_protocol import call_hearing

RECORD = '<0f>7<|box;x1=10;y1=20;x2=30;y2=40;w=100;h=100|><|mask;x=0;y=0;data=21,21,~fixture|>'

class ModelsTests(unittest.TestCase):
    def test_sam_bounds_and_empty_output(self):
        self.assertEqual(parse_boxes(''), [])
        self.assertEqual(parse_boxes(RECORD)[0]['left'], .1)
        for value in [RECORD.replace('x2=30', 'x2=101'), RECORD + ',', 'not geometry']:
            with self.assertRaises(ValueError): parse_boxes(value)
        with self.assertRaises(ValueError): validate_segment({'image_base64': PHOTO, 'prompt': ''})

    @patch('sam_evidence.urlopen')
    def test_sam_stream_and_real_image(self, opener):
        events = [b'data: ' + json.dumps(event).encode() + b'\n' for event in [
            {'type': 'response.output_text.delta', 'delta': RECORD},
            {'type': 'response.completed', 'response': {'status': 'completed'}}]]
        opener.return_value.__enter__.return_value.readline.side_effect = events + [b'']
        answer = segment_evidence({'image_base64': PHOTO, 'prompt': 'plate'}, 'test')
        request = json.loads(opener.call_args.args[0].data)
        self.assertEqual(request['model'], 'sam-3.1')
        self.assertIn(PHOTO, request['input'][0]['content'][1]['image_url'])
        self.assertEqual(len(answer['boxes']), 1)
        self.assertFalse(request['store'])

    @patch('sam_evidence.urlopen')
    def test_incomplete_stream_rejected(self, opener):
        opener.return_value.__enter__.return_value.readline.side_effect = [b'']
        with self.assertRaises(ValueError): segment_evidence({'image_base64': PHOTO, 'prompt': 'plate'}, 'test')

    @patch('court_protocol.urlopen')
    def test_appeal_uses_wonder_with_prior_record(self, opener):
        opener.return_value.__enter__.return_value.read.return_value = json.dumps({
            'status': 'completed', 'model': 'muse-wonder-1.0', 'output': [{'type': 'message', 'role': 'assistant',
            'content': [{'type': 'output_text', 'text': json.dumps(RULING)}]}]}).encode()
        case = {**CASE, 'priorRuling': RULING, 'appealReason': 'Too much', 'appealResponse': 'Fair'}
        result = call_hearing({'action': 'appeal', 'case': case}, 'test', 'muse-spark-1.3')
        body = json.loads(opener.call_args.args[0].data)
        self.assertEqual(body['model'], 'muse-wonder-1.0')
        self.assertEqual(result['model'], 'muse-wonder-1.0')
        self.assertEqual(json.loads(body['input'][0]['content'][0]['text'])['case']['priorRuling'], RULING)
