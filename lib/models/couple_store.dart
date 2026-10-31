import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local preview storage. Online repositories will replace this device-only store.
class CoupleStore extends ChangeNotifier {
  CoupleStore(this.preferences) {
    _load();
    _restoreCourtNames();
  }
  bool get online => false;
  final SharedPreferences preferences;
  String yourName = '';
  String partnerName = '';
  String? storageError;
  DateTime? relationshipStart;
  final List<Map<String, dynamic>> messages = [];
  final List<Map<String, dynamic>> memories = [];
  bool get hasProfile => yourName.isNotEmpty && partnerName.isNotEmpty;
  Future<void> _pending = Future.value();
  int _sequence = 0;

  void _load() {
    try {
      final raw = preferences.getString('couple_preview_v1');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      relationshipStart = DateTime.tryParse(
        data['relationshipStart'] as String? ?? '',
      );
      yourName = data['yourName'] as String;
      partnerName = data['partnerName'] as String;
      messages.addAll(
        (data['messages'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      memories.addAll(
        (data['memories'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
    } catch (_) {
      yourName = '';
      partnerName = '';
      messages.clear();
      memories.clear();
      storageError = 'Your local preview could not be loaded.';
    }
  }

  Future<void> save() {
    final snapshot = jsonEncode({
      'relationshipStart': relationshipStart?.toIso8601String(),
      'yourName': yourName,
      'partnerName': partnerName,
      'messages': messages,
      'memories': memories,
    });
    notifyListeners();
    _pending = _pending.then((_) async {
      try {
        final saved = await preferences.setString(
          'couple_preview_v1',
          snapshot,
        );
        storageError = saved
            ? null
            : 'Changes could not be saved on this device.';
      } catch (_) {
        storageError = 'Changes could not be saved on this device.';
      }
      notifyListeners();
    });
    return _pending;
  }

  void _restoreCourtNames() {
    if (hasProfile) return;
    try {
      final raw = preferences.getString('court_profile_v1');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final names = data['names'] as List;
      if (yourName.isEmpty) yourName = names[0] as String;
      if (partnerName.isEmpty) partnerName = names[1] as String;
    } catch (_) {
      /* Existing couple data remains available if the old profile is invalid. */
    }
  }

  Future<String> addMessage(
    String text, {
    bool summons = false,
    String? photoPath,
    Map<String, dynamic>? replyTo,
  }) async {
    if (text.trim().isEmpty && photoPath == null) {
      throw ArgumentError('A message needs text or a photo.');
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
    messages.add({
      'id': id,
      'text': text.trim(),
      'kind': summons
          ? 'court'
          : photoPath != null
          ? 'photo'
          : 'text',
      'createdAt': DateTime.now().toIso8601String(),
      'status': summons ? 'open' : 'local',
      'sender': 'you',
      'hearted': false,
      'photoPath': ?photoPath,
      if (replyTo != null)
        'replyTo': {
          'id': replyTo['id'],
          'text': replyTo['text'],
          'kind': replyTo['kind'],
        },
    });
    await save();
    return id;
  }

  Future<void> addMemory(String path, String caption) async {
    memories.insert(0, {
      'path': path,
      'caption': caption,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await save();
  }

  Future<void> toggleHeart(String id) {
    final message = messages.firstWhere((entry) => entry['id'] == id);
    message['hearted'] = message['hearted'] != true;
    return save();
  }

  Future<void> finishCourt(String id, Map<String, dynamic> record) {
    final message = messages.firstWhere((entry) => entry['id'] == id);
    message['status'] = 'closed';
    message['courtStatus'] = record['status'];
    message['agreement'] = record['agreement'];
    message['recordId'] = record['id'];
    message['model'] = record['model'];
    message['practice'] = record['practice'];
    return save();
  }

  // Kept for migration of the earlier local preview.
  Future<void> closeCase(String id, String agreement) =>
      finishCourt(id, {'status': 'accepted', 'agreement': agreement});

  List<Map<String, dynamic>> get courtHistory {
    try {
      return (jsonDecode(preferences.getString('court_cases_v1') ?? '[]')
              as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
