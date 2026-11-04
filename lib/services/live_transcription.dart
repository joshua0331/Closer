import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/cloud_couple_store.dart';
import 'backend_access.dart';

/// One bounded microphone stream per server turn, using the existing call track.
class LiveTranscription {
  LiveTranscription(
    this.store,
    this.caseId, {
    required this.onText,
    required this.onState,
    required this.onStatus,
  });
  final CloudCoupleStore store;
  final String caseId;
  final void Function(String) onText;
  final Future<void> Function(Map<String, dynamic>) onState;
  final void Function(String) onStatus;
  static const _capture = MethodChannel('com.jcm.closer/call_audio');
  static const _frames = EventChannel('com.jcm.closer/call_pcm');
  WebSocket? _socket;
  StreamSubscription<dynamic>? _pcm;
  Timer? _limit, _flushTimeout;
  int? _version;
  int _generation = 0;
  bool active = false, finishing = false;

  final Map<int, String> _completed = {};
  String _partial = '';

  Future<void> start(int version, String trackId, int seconds) async {
    if (active || finishing || _version == version) return;
    _version = version;
    active = true;

    _completed.clear();
    _partial = '';
    final generation = ++_generation;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      active = false;
      onStatus(
        'Live transcription currently requires Android. You can type your turn.',
      );
      return;
    }
    onStatus('Connecting live transcriptionâ€¦');
    try {
      final token = store.roomSession ?? await store.user!.getIdToken();
      final http = Uri.parse(
        BackendAccess.instance.url('couple/court/$caseId/voice'),
      );
      final socket = await WebSocket.connect(
        http.replace(scheme: http.scheme == 'https' ? 'wss' : 'ws').toString(),
      ).timeout(const Duration(seconds: 15));
      if (generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.add(jsonEncode({'token': token, 'version': version}));
      _limit = Timer(Duration(seconds: seconds.clamp(1, 120)), () => finish());
      socket.listen(
        (raw) async {
          if (generation != _generation || raw is! String) return;
          final event = jsonDecode(raw) as Map<String, dynamic>;
          switch (event['type']) {
            case 'ready':
              if (finishing) return;
              _pcm = _frames.receiveBroadcastStream().listen(
                (frame) {
                  if (active && !finishing && frame is Uint8List)
                    socket.add(frame);
                },
                onError: (_) =>
                    _fail('Microphone capture failed. You can type your turn.'),
              );
              try {
                await _capture.invokeMethod('start', {'trackId': trackId});
              } catch (_) {
                await _fail(
                  'Could not capture the call microphone. You can type your turn.',
                );
                return;
              }
              if (generation != _generation) {
                await _capture.invokeMethod('stop');
                return;
              }
              onStatus('Listening Â· a 3-second pause ends your turn');
            case 'speechStart':
              _partial = '';
              onStatus('Listeningâ€¦');
            case 'transcript':
              _partial = (event['transcript'] as String?) ?? '';
              onText(
                [
                  ..._completed.values,
                  _partial,
                ].where((s) => s.isNotEmpty).join(' '),
              );
            case 'speechEnd':
              // Speech boundaries finalize transcript segments, not user turns.
              onStatus('Listening · tap End turn when finished');
            case 'speechComplete':
              _completed[event['turnId'] as int? ?? _completed.length] =
                  (event['transcript'] as String?) ?? '';
              _partial = '';
              onText(_completed.values.join(' '));
            case 'submitted':
              onText(event['transcript'] as String? ?? '');
              await cancel();
              onStatus('Turn sent Â· waiting for Metherapy');
              await onState(Map<String, dynamic>.from(event['state'] as Map));
            case 'empty':
              await _fail(
                'No speech detected. Tap Retry voice or type your turn.',
              );
            case 'error':
              await _fail(
                event['message'] as String? ??
                    'Transcription unavailable. You can type your turn.',
              );
          }
        },
        onError: (_) =>
            _fail('Voice connection failed. Your turn was not submitted.'),
        onDone: () {
          if (generation == _generation && active)
            unawaited(
              _fail('Voice connection ended. Retry voice or type your turn.'),
            );
        },
      );
    } catch (_) {
      if (generation == _generation)
        await _fail(
          'Could not connect live transcription. Retry voice or type your turn.',
        );
    }
  }

  Future<void> finish() async {
    if (!active || finishing) return;
    finishing = true;
    _limit?.cancel();
    await _capture.invokeMethod('stop');
    await _pcm?.cancel();
    _pcm = null;
    _socket?.add(jsonEncode({'type': 'endStream'}));
    onStatus('Finishing your transcriptâ€¦');
    _flushTimeout = Timer(
      const Duration(seconds: 18),
      () => _fail('Transcription timed out. Your turn was not submitted.'),
    );
  }

  Future<void> _fail(String message) async {
    await cancel();
    onStatus(message);
  }

  void allowRetry() {
    _version = null;
  }

  Future<void> cancel() async {
    _generation++;
    active = false;
    finishing = false;
    _limit?.cancel();
    _flushTimeout?.cancel();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _capture.invokeMethod('stop');
      } catch (_) {}
    }
    await _pcm?.cancel();
    _pcm = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }
}
