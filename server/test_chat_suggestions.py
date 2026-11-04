import unittest
from unittest.mock import patch, Mock
from chat_suggestions import suggest

class SuggestionsTests(unittest.TestCase):
    def test_uses_recent_text_without_photo_data(self):
        state = {'couple': {'therapyLanguage': 'fil'}, 'messages': [
            {'kind': 'text', 'senderId': 'partner', 'text': 'Kumusta?'},
            {'kind': 'court', 'text': 'private session topic'},
            {'kind': 'photo', 'text': '', 'photoId': 'secret'}]}
        response = Mock()
        response.json.return_value = {'output_text': '{"suggestions":["Mabuti!","Ikaw?"]}'}
        with patch('chat_suggestions.requests.post', return_value=response) as post:
            self.assertEqual(suggest(state, 'me', 'key', 'model')['suggestions'], ['Mabuti!', 'Ikaw?'])
            payload = post.call_args.kwargs['json']
            self.assertIn('Kumusta?', payload['input'])
            self.assertIn('fil', payload['input'])
            self.assertNotIn('secret', payload['input'])
            self.assertNotIn('private session topic', payload['input'])
            self.assertFalse(payload['store'])
    def test_no_canned_fallback_on_failure(self):
        with self.assertRaises(ValueError):
            suggest({'messages': []}, 'me', 'key', 'model')
    def test_invalid_model_response_rejected(self):
        response = Mock()
        response.json.return_value = {'output_text': '{"suggestions":[]}'}
        with patch('chat_suggestions.requests.post', return_value=response):
            with self.assertRaises(ValueError):
                suggest({'messages': [{'kind':'text','text':'hi'}]}, 'me', 'key', 'model')
