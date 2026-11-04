import 'package:closer/models/couple_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Deleting an album persists and preserves other dates and albums',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = CoupleStore(prefs);
      addTearDown(store.dispose);
      await store.addMemory(
        '/one.jpg',
        'One',
        album: 'Trip',
        memoryDate: DateTime(2026, 1, 1),
      );
      await store.addMemory(
        '/two.jpg',
        'Two',
        album: 'Trip',
        memoryDate: DateTime(2026, 1, 1),
      );
      final ids = store.memories
          .map((memory) => memory['id'] as String)
          .toList();
      await store.addMemory(
        '/three.jpg',
        'Three',
        album: 'Trip',
        memoryDate: DateTime(2026, 1, 2),
      );
      await store.addMemory('/four.jpg', 'Four', album: 'Birthday');
      await store.deleteMemories(ids);
      final restored = CoupleStore(prefs);
      addTearDown(restored.dispose);
      expect(restored.memories.map((memory) => memory['caption']), [
        'Four',
        'Three',
      ]);
      await store.deleteMemories(ids);
      expect(store.memories.length, 2);
    },
  );
}
