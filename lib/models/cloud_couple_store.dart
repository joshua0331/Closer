import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../localization/closer_localizations.dart';
import '../services/photo_media.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/couple_store.dart';
import '../services/backend_access.dart';
import '../services/android_widget_sync.dart';
import '../services/notification_service.dart';

class CloudCoupleStore extends CoupleStore {
  CloudCoupleStore(
    super.preferences,
    this.user, {
    this.courtOnly = false,
    this.roomSession,
    this.roomUid,
  }) {
    messages.clear();
    memories.clear();
    yourName = user?.displayName ?? '';
    partnerName = '';
    relationshipStart = null;
  }
  final User? user;
  final String? roomSession, roomUid;
  final bool courtOnly;
  final _client = http.Client();
  Timer? _timer;
  StreamSubscription<String>? _pushTokenSubscription;
  String? _registeredPushId;
  bool _refreshing = false, _closed = false;
  int _pairingGeneration = 0;
  Map<String, dynamic>? couple;
  Map<String, dynamic> profile = {};
  String? avatarPath, partnerAvatarPath;
  String? memoryTagNotice;
  @override
  List<Map<String, dynamic>> get courtHistory => const [];

  @override
  bool get online => true;
  bool get paired => couple != null;
  String get therapyLanguage => couple?['therapyLanguage'] as String? ?? 'en';
  String get uid => roomUid ?? user!.uid;
  Map<String, dynamic> get locations =>
      Map<String, dynamic>.from(couple?['locations'] as Map? ?? {});
  String? get partnerUid => (couple?['members'] as List?)
      ?.cast<String>()
      .where((id) => id != uid)
      .firstOrNull;

  DateTime? _lastDeviceSync;
  Map<String, dynamic>? get partnerDeviceStatus {
    final value = (couple?['deviceStatuses'] as Map?)?[partnerUid];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<void> _syncDeviceStatus() async {
    if (!Platform.isAndroid || !paired || _closed) return;
    final now = DateTime.now();
    if (_lastDeviceSync != null &&
        now.difference(_lastDeviceSync!).inSeconds < 30)
      return;
    _lastDeviceSync = now;
    try {
      final value = await const MethodChannel('com.jcm.closer/device_status')
          .invokeMapMethod<String, dynamic>('read');
      if (value != null && paired && !_closed) {
        await action({'action': 'device_status', ...value});
      }
    } catch (_) {
      // Optional telemetry must never interrupt chat or pairing.
    }
  }

  Future<http.Response> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = roomSession ?? await user!.getIdToken();
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
                    : body?['operation'] == 'memory_tags'
                    ? 65
                    : body?['operation'] == 'review' ||
                          body?['operation'] == 'opening' ||
                          body?['operation'] == 'facilitate'
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
    unawaited(_syncNotificationTokenIfAllowed());
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
  }

  Future<void> _syncNotificationTokenIfAllowed() async {
    try {
      if (!await NotificationService.instance.isEnabled()) return;
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await registerPushToken();
      }
    } catch (_) {
      // Push is optional; pairing, chat, maps and saved places remain usable.
    }
  }

  void _listenForPushTokenRefresh() {
    try {
      _pushTokenSubscription ??= FirebaseMessaging.instance.onRegistered.listen(
        (pushId) {
          if (!_closed && paired && pushId != _registeredPushId) {
            unawaited(
              action({'action': 'push_registration', 'installationId': pushId})
                  .then((value) {
                    _registeredPushId = pushId;
                    return value;
                  })
                  .catchError((_) => <String, dynamic>{}),
            );
          }
        },
      );
    } catch (_) {
      // Firebase Messaging is unavailable on some preview platforms.
    }
  }

  Future<void> unregisterPushToken() async {
    await action({'action': 'push_unregistration'});
    _registeredPushId = null;
    await _pushTokenSubscription?.cancel();
    _pushTokenSubscription = null;
  }

  Future<void> registerPushToken() async {
    final registeredId = FirebaseMessaging.instance.onRegistered.first;
    _listenForPushTokenRefresh();
    await FirebaseMessaging.instance.register();
    final pushId = await registeredId.timeout(const Duration(seconds: 15));
    if (pushId == _registeredPushId) return;
    await action({'action': 'push_registration', 'installationId': pushId});
    _registeredPushId = pushId;
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

  void resumeBackgroundSharing() {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    refresh();
  }

  Future<void> refresh() async {
    if (_refreshing || _closed) return;
    _refreshing = true;
    final generation = _pairingGeneration;
    try {
      final response = await request('couple/state');
      final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      if (_closed || generation != _pairingGeneration) return;
      profile = Map<String, dynamic>.from(data['profile'] as Map);
      couple = data['couple'] == null
          ? null
          : Map<String, dynamic>.from(data['couple'] as Map);
      if (couple != null) {
        await CloserLocaleController.saveLanguage(preferences, therapyLanguage);
      } else {
        CloserLocaleController.setLanguage(
          preferences.getString(CloserLocaleController.preferenceKey),
        );
      }
      unawaited(_syncDeviceStatus());
      final avatarIds = Map<String, dynamic>.from(
        couple?['avatars'] as Map? ?? {},
      );
      avatarPath = couple != null && profile['avatarPhotoId'] is String
          ? await photoPath(profile['avatarPhotoId'] as String)
          : null;
      final partnerPhoto = avatarIds[partnerUid];
      partnerAvatarPath = partnerPhoto is String
          ? await photoPath(partnerPhoto)
          : null;
      yourName = profile['name'] as String? ?? user?.displayName ?? '';
      partnerName = couple == null
          ? ''
          : (couple!['names'] as Map)[partnerUid] as String? ?? 'Partner';
      relationshipStart = DateTime.tryParse(
        couple?['anniversary'] as String? ?? '',
      );
      final nextMessages = <Map<String, dynamic>>[];
      for (final raw in data['messages'] as List) {
        final item = Map<String, dynamic>.from(raw as Map);
        if (courtOnly && item['kind'] != 'court') continue;
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
      for (final raw in (courtOnly ? [] : data['memories'] as List)) {
        final item = Map<String, dynamic>.from(raw as Map);
        if (item['photoId'] == null) continue;
        item['caption'] = item['text'];
        item['addedBy'] = item['senderId'] == uid ? yourName : partnerName;
        item['path'] = await photoPath(item['photoId'] as String);
        nextMemories.add(item);
      }
      if (_closed || generation != _pairingGeneration) return;
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
      if (!_closed) {
        unawaited(AndroidWidgetSync.sync(this));
        notifyListeners();
      }
    }
  }

  Future<String> photoPath(String id) async {
    if (kIsWeb) {
      final response = await request('couple/photo/$id');
      return 'data:image/jpeg;base64,${base64Encode(response.bodyBytes)}';
    }
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
    final bytes = await readPhoto(path);
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

  Future<Map<String, dynamic>> callSignal(
    String id, {
    int after = 0,
    Map<String, dynamic>? body,
  }) async {
    final response = await request(
      'couple/court/$id/call?after=$after',
      body: body,
    );
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<String> invite() async =>
      (await action({'action': 'invite'}))['code'] as String;
  Future<void> join(String code) async {
    await action({'action': 'join', 'code': code.trim()});
    await refresh();
  }

  Future<void> setTherapyLanguage(String language) async {
    await action({'action': 'therapy_language', 'language': language});
    await CloserLocaleController.saveLanguage(preferences, language);
    await refresh();
  }

  Future<void> unpair() async {
    await action({'action': 'unpair'});
    _pairingGeneration++;
    _registeredPushId = null;
    await preferences.setBool('closer_location_share_$uid', false);
    profile.remove('coupleId');
    profile.remove('avatarPhotoId');
    couple = null;
    partnerName = '';
    avatarPath = partnerAvatarPath = null;
    relationshipStart = null;
    messages.clear();
    memories.clear();
    storageError = null;
    await AndroidWidgetSync.clearDistance();
    notifyListeners();
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

  Future<void> saveAvatar(String path) async {
    final id = await upload(path);
    await action({'action': 'profile', 'name': yourName, 'avatarPhotoId': id});
    await refresh();
  }

  @override
  Future<String> addMessage(
    String text, {
    bool summons = false,
    String? photoPath,
    Map<String, dynamic>? replyTo,
    String therapyLanguage = 'en',
  }) async {
    final id = newRequestId();
    final photoId = photoPath == null ? null : await upload(photoPath);
    await action({
      'action': 'message',
      'id': id,
      'text': text.trim(),
      'summons': summons,
      if (summons) 'therapyLanguage': therapyLanguage,
      'photoId': photoId,
      'replyId': replyTo?['id'],
    });
    await refresh();
    return id;
  }

  @override
  Future<void> addMemory(
    String path,
    String caption, {
    String album = '',
    DateTime? memoryDate,
    List<String> tags = const [],
    bool aiTags = false,
  }) async {
    await _requireMemorySupport();
    final id = await upload(path);
    final memoryId = newRequestId();
    await action({
      'action': 'memory',
      'id': memoryId,
      'text': caption,
      'photoId': id,
      'album': album,
      'memoryDate': (memoryDate ?? DateTime.now()).toIso8601String(),
      'tags': tags,
    });
    if (aiTags) {
      try {
        await tagMemory(memoryId, id);
      } catch (_) {
        memoryTagNotice = 'Photo saved to your album. Automatic tags are unavailable right now.';
      }
    }
    await refresh();
  }

  @override
  Future<void> deleteMemories(List<String> ids) async {
    await _requireMemorySupport();
    await action({'action': 'delete_memories', 'ids': ids});
    await refresh();
  }

  Future<void> _requireMemorySupport() async {
    try {
      final capabilities = await action({'action': 'memory_capabilities'});
      if (capabilities['albums'] == true &&
          capabilities['deleteMemories'] == true) {
        return;
      }
    } catch (error) {
      if (!error.toString().contains('Unknown action')) rethrow;
    }
    throw Exception(
      'The shared server needs an update before albums can be changed. Please contact the app administrator.',
    );
  }

  Future<List<String>> tagMemory(String memoryId, String photoId) async {
    final response = await request(
      'couple/memory-tags',
      body: {
        'memoryId': memoryId,
        'photoId': photoId,
        'operation': 'memory_tags',
      },
    );
    return List<String>.from(
      (jsonDecode(response.body) as Map)['tags'] as List,
    );
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
    _pushTokenSubscription?.cancel();
    _client.close();
    super.dispose();
  }
}
