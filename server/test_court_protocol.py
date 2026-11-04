import base64
import copy
import json
import unittest
from unittest.mock import patch
from court_protocol import call_hearing, validate_hearing, validate_answer

PHOTO = base64.b64encode(b'\xff\xd8\xff' + b'fixture' * 4).decode()
CASE = {'therapyLanguage': 'en','topic': 'Chores', 'requestedRemedy': 'Cook dinner once', 'names': ['Alex', 'Sam'],
        'statements': ['I did dishes', 'I did laundry'], 'crossQuestions': ['When?', 'Why?'],
        'crossAnswers': ['Yesterday', 'It was needed'], 'rebuttals': ['Clarification', 'Response'],
        'judgeQuestions': ['What matters?', 'What is feasible?'], 'judgeAnswers': ['Fairness', 'Cook once'],
        'evidence': [{'id': 'E1', 'owner': 0, 'caption': 'Sink after dinner', 'image_base64': PHOTO}],
        'appealReason': '', 'appealResponse': '', 'priorRuling': None}
REVIEW = [{'id': 'E1', 'observation': 'A sink with dishes is visible.', 'limitation': 'Author and time cannot be verified.'}]
RULING = {'decision': 'reduce', 'requestedRemedy': 'Cook dinner once', 'proposedRemedy': 'Share dinner prep once',
          'reasoning': 'Both accounts matter.', 'uncertainties': 'Image context is unverified.', 'evidenceReview': REVIEW}

class HearingTests(unittest.TestCase):
    def test_validates_bounded_attributed_evidence(self):
        normalized = validate_hearing({'action': 'questions', 'case': CASE})
        self.assertTrue(normalized['case']['evidence'][0]['image_url'].startswith('data:image/jpeg;base64,'))
        for mutation in [
            {'evidence': [{**CASE['evidence'][0], 'owner': 2}]},
            {'evidence': CASE['evidence'] * 2},
            {'evidence': [{**CASE['evidence'][0], 'image_base64': 'https://example.com/private.jpg'}]},
            {'requestedRemedy': ''}, {'judgeAnswers': ['', '']},
        ]:
            action = 'verdict' if 'judgeAnswers' in mutation else 'questions'
            with self.assertRaises(ValueError):
                validate_hearing({'action': action, 'case': {**CASE, **mutation}})

    def test_missing_or_invented_evidence_and_changed_original_request_fail(self):
        for answer in [{**RULING, 'evidenceReview': []},
                       {**RULING, 'evidenceReview': [{**REVIEW[0], 'id': 'E99'}]},
                       {**RULING, 'requestedRemedy': 'Changed request'}]:
            with self.assertRaises(ValueError):
                validate_answer(answer, 'verdict', ['E1'], CASE['requestedRemedy'])

    @patch('court_protocol.urlopen')
    def test_real_image_parts_and_all_testimony_reach_muse(self, opener):
        opener.return_value.__enter__.return_value.read.return_value = json.dumps({
            'status': 'completed', 'model': 'muse-spark-1.3', 'output': [{'type': 'message', 'role': 'assistant',
                'content': [{'type': 'output_text', 'text': json.dumps(RULING)}]}]}).encode()
        result = call_hearing({'action': 'verdict', 'case': CASE}, 'test-key', 'muse-spark-1.3')
        request = opener.call_args.args[0]
        body = json.loads(request.data)
        content = body['input'][0]['content']
        images = [item for item in content if item['type'] == 'input_image']
        self.assertEqual(len(images), 1)
        self.assertIn(PHOTO, images[0]['image_url'])
        record = json.loads(content[0]['text'])['case']
        for field in ['statements', 'crossQuestions', 'crossAnswers', 'rebuttals', 'judgeAnswers']:
            self.assertEqual(record[field], CASE[field])
        self.assertNotIn('image_url', record['evidence'][0])
        self.assertFalse(body['store'])
        self.assertEqual(result['result']['requestedRemedy'], CASE['requestedRemedy'])

    @patch('court_protocol.urlopen')
    def test_token_limited_response_retries_without_accepting_partial_answer(self, opener):
        complete = {'status': 'completed', 'model': 'muse-spark-1.3', 'output': [{'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': json.dumps(RULING)}]}]}
        opener.return_value.__enter__.return_value.read.side_effect = [
            json.dumps({'status': 'incomplete', 'incomplete_details': {'reason': 'max_output_tokens'}}).encode(),
            json.dumps(complete).encode()]
        result = call_hearing({'action': 'verdict', 'case': CASE}, 'test-key', 'muse-spark-1.3')
        self.assertEqual(opener.call_count, 2)
        self.assertEqual(json.loads(opener.call_args.args[0].data)['max_output_tokens'], 14000)
        self.assertEqual(result['result'], RULING)

    def test_appeal_requires_prior_ruling_and_both_sides(self):
        with self.assertRaises(ValueError):
            validate_hearing({'action': 'appeal', 'case': CASE})
        appeal = {**copy.deepcopy(CASE), 'appealReason': 'Too much', 'appealResponse': 'Once is fair', 'priorRuling': RULING}
        result = validate_hearing({'action': 'appeal', 'case': appeal})
        self.assertEqual(result['case']['priorRuling'], RULING)
        self.assertEqual(result['case']['appealResponse'], 'Once is fair')

if __name__ == '__main__':
    unittest.main()
