import json
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from judge_server import JudgeServer, call_meta, extract_text, validate

CASE = {'topic': 'Chores', 'names': ['Alex', 'Sam'],
        'statements': ['I do the dishes', 'I do the laundry']}

class JudgeTests(unittest.TestCase):
    def test_rejects_missing_or_extra_partner_data(self):
        for payload in [[], {}, {**CASE, 'names': ['One']}, {**CASE, 'photos': ['x']},
                        {**CASE, 'topic': ' '}, {**CASE, 'statements': ['x' * 2001, 'ok']}]:
            with self.assertRaises(ValueError):
                validate(payload)

    def test_only_assistant_output_is_displayed(self):
        data = {'status': 'completed', 'output': [
            {'type': 'reasoning', 'summary': [{'text': 'hidden reasoning'}]},
            {'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': 'Take turns.'}]}]}
        self.assertEqual(extract_text(data), 'Take turns.')
        with self.assertRaises(ValueError):
            extract_text({**data, 'status': 'incomplete'})

    @patch('judge_server.urlopen')
    def test_calls_meta_without_photos_and_returns_real_model_identity(self, opener):
        opener.return_value.__enter__.return_value.read.return_value = json.dumps({
            'status': 'completed', 'model': 'muse-spark-1.3',
            'output': [{'type': 'message', 'role': 'assistant',
                        'content': [{'type': 'output_text', 'text': 'A fair next step.'}]}]}).encode()
        result = call_meta(CASE, 'test-key', 'muse-spark-1.3')
        request = opener.call_args.args[0]
        self.assertEqual(request.full_url, 'https://api.meta.ai/v1/responses')
        body = json.loads(request.data)
        self.assertFalse(body['store'])
        self.assertNotIn('photos', json.loads(body['input']))
        self.assertEqual(result['model'], 'muse-spark-1.3')

    def test_http_auth_and_invalid_case_never_call_model(self):
        server = JudgeServer(('127.0.0.1', 0), 'test-key', 'a' * 24)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f'http://127.0.0.1:{server.server_port}/judge'
            for token, payload, status in [('wrong', CASE, 401), ('a' * 24, {}, 400)]:
                request = Request(url, json.dumps(payload).encode(), headers={'Authorization': f'Bearer {token}'})
                with patch('judge_server.call_meta') as model, self.assertRaises(HTTPError) as caught:
                    urlopen(request, timeout=3)
                self.assertEqual(caught.exception.code, status)
                caught.exception.close()
                model.assert_not_called()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

if __name__ == '__main__':
    unittest.main()
