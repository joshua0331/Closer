import unittest
from unittest.mock import MagicMock

from couple_data import CoupleData
from demo_security import AccessError


class MemoryDeletionTest(unittest.TestCase):
    def setUp(self):
        self.data = CoupleData.__new__(CoupleData)
        self.data.db = MagicMock()
        self.data.member = MagicMock(return_value=('our_couple', {}))
        self.data.state = MagicMock(return_value={})

    def test_deletes_only_selected_memories_in_authenticated_couple(self):
        self.data.action('alice', {'action': 'delete_memories', 'ids': ['one', 'two', 'one']})
        self.data.member.assert_called_once_with('alice')
        root = self.data.db.collection.return_value.document.return_value
        root.collection.assert_called_with('memories')
        self.assertEqual(self.data.db.batch.return_value.delete.call_count, 2)
        self.data.db.batch.return_value.commit.assert_called_once()

    def test_rejects_invalid_ids_before_writing(self):
        for ids in ([], ['../other'], [None], 'one'):
            with self.assertRaises(AccessError):
                self.data.action('alice', {'action': 'delete_memories', 'ids': ids})
        self.data.db.batch.assert_not_called()

    def test_court_guests_cannot_delete(self):
        with self.assertRaises(AccessError):
            self.data.action('room_guest', {'action': 'delete_memories', 'ids': ['one']})
        self.data.member.assert_not_called()

    def test_album_support_is_reported_for_authenticated_members(self):
        result = self.data.action('alice', {'action': 'memory_capabilities'})
        self.assertEqual(result, {'albums': True, 'deleteMemories': True})
        self.data.member.assert_called_once_with('alice')
        self.data.db.batch.assert_not_called()

    def test_new_photo_keeps_selected_album_and_date(self):
        root = self.data.db.collection.return_value.document.return_value
        record = root.collection.return_value.document.return_value
        record.get.return_value.exists = False
        self.data.action('alice', {
            'action': 'memory', 'id': 'new_photo', 'text': 'Different caption',
            'album': 'Window', 'memoryDate': '2026-11-03T00:00:00',
        })
        saved = record.create.call_args.args[0]
        self.assertEqual(saved['album'], 'Window')
        self.assertEqual(saved['memoryDate'], '2026-11-03T00:00:00')
        self.assertEqual(saved['text'], 'Different caption')
