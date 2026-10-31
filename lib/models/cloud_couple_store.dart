import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/couple_store.dart';
import '../services/backend_access.dart';

class CloudCoupleStore extends CoupleStore {
  CloudCoupleStore(super.preferences, this.user) {
    messages.clear();
    memories.clear();
    yourName = user.displayName ?? '';
    partnerName = '';
    relationshipStart = null;
  }
  final User user;
  final _client = http.Client();
  Timer? _timer;
  bool _refreshing = false, _closed = false;
  Map<String, dynamic>? couple;
  Map<String, dynamic> profile = {};
  @override
  List<Map<String, dynamic>> get courtHistory => const [];

  @override
  bool get online => true;
  bool get paired => couple != null;
  String get uid => user.uid;
  Map<String, dynamic> get locations =>
      Map<String, dynamic>.from(couple?['locations'] as Map? ?? {});
  String? get partnerUid => (couple?['members'] as List?)
      ?.cast<String>()
      .where((id) => id != uid)
      .firstOrNull;

  Future<http.Response> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await user.getIdToken();
    final uri = Uri.parse(BackendAccess.instance.url(path));
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'X-Demo-Session': BackendAccess.instance.token,
      'X-Request-ID': newRequestId(),
    };
    final response =
        await (body == null
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(
              Duration(
                seconds: body?['operation'] == 'art'
                    ? 220
                    : body?['operation'] == 'review'
                    ? 100
                    : 35,
              ),
            );
    if (response.statusCode != 200) {
      String message = 'Could not connect. Check your internet and retry.';
      try {
        message = (jsonDecode(response.body) as Map)['error'] as String;
      } catch (_) {}
      throw Exception(message);
    }
    return response;
  }

  Future<Map<String, dynamic>> action(Map<String, dynamic> body) async {
    final response = await request('couple/action', body: body);
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<void> start() async {
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
  }

  void pause() {
    _timer?.cancel();
  }

  void resume() {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
    refresh();
  }

  Future<void> refresh() async {
    if (_refreshing || _closed) return;
    _refreshing = true;
    try {
      final response = await request('couple/state');
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (_closed) return;
      profile = Map<String, dynamic>.from(data['profile'] as Map);
      couple = data['couple'] == null
          ? null
          : Map<String, dynamic>.from(data['couple'] as Map);
      yourName = profile['name'] as String? ?? user.displayName ?? '';
      partnerName = couple == null
          ? ''
          : (couple!['names'] as Map)[partnerUid] as String? ?? 'Partner';
      relationshipStart = DateTime.tryParse(
        couple?['anniversary'] as String? ?? '',
      );
      final nextMessages = <Map<String, dynamic>>[];
      for (final raw in data['messages'] as List) {
        final item = Map<String, dynamic>.from(raw as Map);
        item['sender'] = item['senderId'] == uid ? 'you' : 'partner';
        item['heartedByMe'] = (item['hearts'] as List? ?? []).contains(uid);
        item['hearted'] = (item['hearts'] as List? ?? []).isNotEmpty;
        item['status'] ??= 'sent';
        if (item['photoId'] != null) {
          item['photoPath'] = await photoPath(item['photoId'] as String);
        }
        nextMessages.add(item);
      }
      final nextMemories = <Map<String, dynamic>>[];
      for (final raw in data['memories'] as List) {
        final item = Map<String, dynamic>.from(raw as Map);
        if (item['photoId'] == null) continue;
        item['caption'] = item['text'];
        item['path'] = await photoPath(item['photoId'] as String);
        nextMemories.add(item);
      }
      if (_closed) return;
      messages
        ..clear()
        ..addAll(nextMessages);
      memories
        ..clear()
        ..addAll(nextMemories);
      storageError = null;
    } catch (e) {
      if (!_closed) {
        storageError =
            'Sync paused: ${e.toString().replaceFirst('Exception: ', '')}';
      }
    } finally {
      _refreshing = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<String> photoPath(String id) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/closer_cloud/$uid/$id.jpg');
    if (!await file.exists()) {
      final response = await request('couple/photo/$id');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: true);
    }
    return file.path;
  }

  Future<String> upload(String path) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length > 4000000) {
      throw Exception('Choose a photo smaller than 4 MB.');
    }
    final response = await request(
      'couple/photo',
      body: {'image_base64': base64Encode(bytes)},
    );
    return (jsonDecode(response.body) as Map)['id'] as String;
  }

  Future<Map<String, dynamic>> hearing(
    String id, {
    Map<String, dynamic>? body,
  }) async {
    final response = await request('couple/court/$id', body: body);
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<String> invite() async =>
      (await action({'action': 'invite'}))['code'] as String;
  Future<void> join(String code) async {
    await action({'action': 'join', 'code': code.trim()});
    await refresh();
  }

  @override
  Future<void> save() async {
    await action({'action': 'profile', 'name': yourName});
    if (paired && relationshipStart != null) {
      await action({
        'action': 'anniversary',
        'date': relationshipStart!.toIso8601String(),
      });
    }
    await refresh();
  }

  @override
  Future<String> addMessage(
    String text, {
    bool summons = false,
    String? photoPath,
    Map<String, dynamic>? replyTo,
  }) async {
    final id = newRequestId();
    final photoId = photoPath == null ? null : await upload(photoPath);
    await action({
      'action': 'message',
      'id': id,
      'text': text.trim(),
      'summons': summons,
      'photoId': photoId,
      'replyId': replyTo?['id'],
    });
    await refresh();
    return id;
  }

  @override
  Future<void> addMemory(String path, String caption) async {
    final id = await upload(path);
    await action({
      'action': 'memory',
      'id': newRequestId(),
      'text': caption,
      'photoId': id,
    });
    await refresh();
  }

  @override
  Future<void> toggleHeart(String id) async {
    final item = messages.firstWhere((m) => m['id'] == id);
    await action({
      'action': 'heart',
      'id': id,
      'liked': item['heartedByMe'] != true,
    });
    await refresh();
  }

  Future<void> shareLocation(Map<String, dynamic>? point) async {
    await action({'action': 'location', 'location': point});
    await refresh();
  }

  // Shared hearing closure is published by the server only after participant responses.
  @override
  Future<void> finishCourt(String id, Map<String, dynamic> record) async {
    await refresh();
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}
