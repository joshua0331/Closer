import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/cloud_couple_store.dart';

/// Connects the two partners with a voice-only WebRTC peer connection.
/// Only SDP and ICE setup data pass through Closer's backend; audio remains
/// encrypted peer-to-peer and is never saved by the app.
class LiveCoupleCall extends ChangeNotifier {
  LiveCoupleCall(this.store, this.caseId);

  final CloudCoupleStore store;
  final String caseId;

  RTCPeerConnection? _peer;
  MediaStream? _local;
  Timer? _poll;
  String? callId;
  String status = 'not_started';
  String? error;
  bool _initiator = false;
  bool _remoteDescriptionSet = false;
  bool _manualMuted = false;
  bool _turnAllowed = false;
  bool muted = true;
  int _lastSignal = 0;
  bool _closed = false;
  bool _working = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  bool get joined =>
      callId != null && status != 'ended' && status != 'not_started';
  String? get microphoneTrackId => _local?.getAudioTracks().firstOrNull?.id;
  bool get connected => status == 'connected';
  bool get waiting => status == 'waiting' || status == 'connecting';

  Future<void> join() async {
    if (joined || _working) return;
    _working = true;
    error = null;
    notifyListeners();
    try {
      _lastReadyReport = null;
      _remoteDescriptionSet = false;
      _manualMuted = false;
      _turnAllowed = false;
      _lastSignal = 0;
      _pendingCandidates.clear();
      final joinedCall = await store.callSignal(
        caseId,
        body: const {
          'operation': 'join',
          'aiConsent': true,
          'audioConsent': true,
        },
      );
      callId = joinedCall['callId'] as String;
      _initiator = joinedCall['startedBy'] == store.uid;
      status = 'waiting';

      final configuration = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };
      _peer = await createPeerConnection(configuration);
      _peer!.onConnectionState = (state) {
        final stateName = state.toString().toLowerCase();
        if (stateName.contains('disconnected')) {
          status = 'connecting';
        } else if (stateName.contains('connected')) {
          status = 'connected';
          error = null;
          unawaited(_reportReady());
        } else if (stateName.contains('failed')) {
          status = 'failed';
          error = 'The phones could not connect directly. Try the same Wi-Fi or a different network.';
        } else if (stateName.contains('connecting')) {
          if (status != 'connected') status = 'connecting';
        } else if (stateName.contains('disconnected')) {
          if (status == 'connected') status = 'connecting';
        }
        _applyMute();
        notifyListeners();
      };
      _peer!.onIceCandidate = (candidate) {
        final currentId = callId;
        final candidateText = candidate.candidate;
        if (currentId == null ||
            candidateText == null ||
            candidateText.isEmpty) {
          return;
        }
        unawaited(_sendCandidate(currentId, candidate));
      };
      _peer!.onTrack = (_) {
        // The audio receiver is played by the WebRTC audio device module.
        notifyListeners();
      };

      _local = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      for (final track in _local!.getAudioTracks()) {
        track.enabled = false;
        await _peer!.addTrack(track, _local!);
      }
      await Helper.setSpeakerphoneOn(true);

      if (_initiator) {
        await _sendOffer();
      }
      status = 'connecting';
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _sync());
      await _sync();
      notifyListeners();
    } catch (exception) {
      status = 'failed';
      error = exception.toString().replaceFirst('Exception: ', '');
      await _closeMedia();
      notifyListeners();
    } finally {
      _working = false;
    }
  }

  void setTurnAllowed(bool allowed) {
    if (_turnAllowed == allowed) return;
    _turnAllowed = allowed;
    _applyMute();
    notifyListeners();
  }

  void toggleMute() {
    if (!_turnAllowed) return;
    _manualMuted = !_manualMuted;
    _applyMute();
    notifyListeners();
  }

  void _applyMute() {
    muted = !_turnAllowed || _manualMuted || !connected;
    for (final track
        in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  Future<void> _sendOffer() async {
    final peer = _peer;
    final id = callId;
    if (peer == null || id == null) return;
    final offer = await peer.createOffer({'offerToReceiveAudio': 1});
    await peer.setLocalDescription(offer);
    await store.callSignal(
      caseId,
      body: {'operation': 'offer', 'callId': id, 'sdp': offer.sdp ?? ''},
    );
  }

  Future<void> _sendAnswer() async {
    final peer = _peer;
    final id = callId;
    if (peer == null || id == null) return;
    final answer = await peer.createAnswer({'offerToReceiveAudio': 1});
    await peer.setLocalDescription(answer);
    await store.callSignal(
      caseId,
      body: {'operation': 'answer', 'callId': id, 'sdp': answer.sdp ?? ''},
    );
  }

  Future<void> _sendCandidate(String id, RTCIceCandidate candidate) async {
    try {
      await store.callSignal(
        caseId,
        body: {
          'operation': 'candidate',
          'callId': id,
          'candidate': candidate.toMap(),
        },
      );
    } catch (exception) {
      if (!_closed) {
        error = exception.toString().replaceFirst('Exception: ', '');
        notifyListeners();
      }
    }
  }

  DateTime? _lastReadyReport;

  Future<void> _reportReady() async {
    if (_lastReadyReport != null &&
        DateTime.now().difference(_lastReadyReport!).inSeconds < 6)
      return;
    if (!connected || callId == null || _closed) return;
    try {
      await store.callSignal(
        caseId,
        body: {'operation': 'ready', 'callId': callId},
      );
      _lastReadyReport = DateTime.now();
    } catch (_) {
      /* Retry with the next call heartbeat. */
    }
  }

  Future<void> _sync() async {
    if (_closed || callId == null || _working) return;
    _working = true;
    try {
      if (connected) await _reportReady();
      final data = await store.callSignal(caseId, after: _lastSignal);
      if (_closed) return;
      if (data['callId'] != callId) {
        status = 'ended';
        _poll?.cancel();
        await _closeMedia();
        notifyListeners();
        return;
      }
      if (data['status'] == 'ended') {
        status = 'ended';
        _poll?.cancel();
        await _closeMedia();
        notifyListeners();
        return;
      }
      if (data['status'] == 'waiting' && status != 'connected') {
        status = 'waiting';
      }

      final offer = data['offer'];
      if (!_initiator && !_remoteDescriptionSet && offer is Map) {
        final sdp = offer['sdp'];
        if (sdp is String && sdp.isNotEmpty) {
          await _peer?.setRemoteDescription(
            RTCSessionDescription(sdp, offer['type'] as String? ?? 'offer'),
          );
          _remoteDescriptionSet = true;
          await _drainCandidates();
          await _sendAnswer();
        }
      }
      final answer = data['answer'];
      if (_initiator && !_remoteDescriptionSet && answer is Map) {
        final sdp = answer['sdp'];
        if (sdp is String && sdp.isNotEmpty) {
          await _peer?.setRemoteDescription(
            RTCSessionDescription(sdp, answer['type'] as String? ?? 'answer'),
          );
          _remoteDescriptionSet = true;
          await _drainCandidates();
        }
      }

      final signals = (data['signals'] as List? ?? const []);
      for (final raw in signals) {
        if (raw is! Map) continue;
        final sequence = raw['sequence'];
        if (sequence is int && sequence > _lastSignal) _lastSignal = sequence;
        if (raw['sender'] == store.uid) continue;
        final candidateData = raw['candidate'];
        if (candidateData is! Map) continue;
        final candidate = RTCIceCandidate(
          candidateData['candidate'] as String?,
          candidateData['sdpMid'] as String?,
          candidateData['sdpMLineIndex'] as int?,
        );
        if (_remoteDescriptionSet) {
          await _peer?.addCandidate(candidate);
        } else {
          _pendingCandidates.add(candidate);
        }
      }
      _applyMute();
      notifyListeners();
    } catch (exception) {
      if (!_closed) {
        error = exception.toString().replaceFirst('Exception: ', '');
        notifyListeners();
      }
    } finally {
      _working = false;
    }
  }

  Future<void> _drainCandidates() async {
    final queued = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in queued) {
      await _peer?.addCandidate(candidate);
    }
  }

  Future<void> end() async {
    final id = callId;
    _poll?.cancel();
    status = 'ended';
    muted = true;
    if (id != null) {
      try {
        await store.callSignal(
          caseId,
          body: {'operation': 'end', 'callId': id},
        );
      } catch (_) {}
    }
    await _closeMedia();
    notifyListeners();
  }

  Future<void> _closeMedia() async {
    _poll?.cancel();
    for (final track in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _local?.dispose();
    _local = null;
    final peer = _peer;
    _peer = null;
    await peer?.close();
    await peer?.dispose();
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    final id = callId;
    if (id != null && status != 'ended') {
      unawaited(
        store
            .callSignal(caseId, body: {'operation': 'end', 'callId': id})
            .catchError((_) => <String, dynamic>{}),
      );
    }
    unawaited(_closeMedia());
    super.dispose();
  }
}
