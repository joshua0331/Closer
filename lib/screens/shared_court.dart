import '../services/live_transcription.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import '../localization/closer_localizations.dart';
import '../services/photo_media.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

import '../models/cloud_couple_store.dart';
import '../services/backend_access.dart';
import '../services/court_performance.dart';
import '../services/judge_service.dart';
import '../services/live_couple_call.dart';
import 'evidence_highlights.dart';

const _turns = <int, int>{
  0: 0,
  1: 0,
  2: 1,
  3: 0,
  4: 1,
  5: 1,
  6: 0,
  7: 0,
  8: 1,
  10: 0,
  11: 1,
  14: 1,
  15: 0,
};
const _titles = [
  'What would you like to change?',
  'Your perspective',
  'Your partner’s perspective',
  'Ask your partner',
  'Listen and respond',
  'Ask a follow-up',
  'Listen and respond',
  'What matters most to you?',
  'What matters most to your partner?',
  'Questions from Metherapy',
  'Your reflection',
  'Your partner’s reflection',
  'Metherapy is considering both perspectives',
  'A possible next step',
  'Ask to revisit the suggestion',
  'Share what feels unworkable',
  'Metherapy is taking another look',
  'An adjusted next step',
  'Session complete',
];

class SharedCourt extends StatefulWidget {
  const SharedCourt({
    super.key,
    required this.store,
    required this.caseId,
    this.roomInvite,
    this.onLobby,
  });
  final CloudCoupleStore store;
  final String caseId;
  final String? roomInvite;
  final VoidCallback? onLobby;
  @override
  State<SharedCourt> createState() => _SharedCourtState();
}

class _SharedCourtState extends State<SharedCourt> with WidgetsBindingObserver {
  Map<String, dynamic>? _case;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _therapistVoice = FlutterTts();
  late final LiveCoupleCall _liveCall;
  late final LiveTranscription _voice;
  String _voiceStatus = '';
  String? _playbackAcknowledged;
  int? _lastSpokenPhase;
  String? _lastSpokenResponseId;
  int? _facilitatorAttemptedVersion;
  int _speechGeneration = 0;
  Timer? _facilitatorTimer;
  bool _facilitatorRequestRunning = false;
  bool _therapistSpeaking = false;
  String? _configuredVoiceLocale;
  bool _listening = false;
  VoidCallback? _callDetailsRebuild;
  double _clockOffset = 0;
  final _text = TextEditingController(), _caption = TextEditingController();
  Timer? _poll, _clock;
  int _statePollSeconds = 5;
  bool _busy = false, _loading = false, _inCourtMode = false;
  String? _error;
  final Map<String, String> _photos = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _liveCall = LiveCoupleCall(widget.store, widget.caseId)
      ..addListener(_onCallChanged);
    _voice = LiveTranscription(
      widget.store,
      widget.caseId,
      onText: (text) {
        if (mounted) setState(() => _text.text = text);
      },
      onState: (state) async {
        if (mounted) await _apply(state);
      },
      onStatus: (status) {
        if (mounted) setState(() => _voiceStatus = status);
      },
    );
    _refresh();
    _poll = Timer.periodic(
      Duration(seconds: _statePollSeconds),
      (_) => _refresh(),
    );
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _syncCallTurn();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_voice.cancel());
    _liveCall.removeListener(_onCallChanged);
    _liveCall.dispose();
    _speechGeneration++;
    unawaited(_therapistVoice.stop());
    _facilitatorTimer?.cancel();
    _callDetailsRebuild = null;
    _poll?.cancel();
    _clock?.cancel();
    _text.dispose();
    _caption.dispose();
    unawaited(_speech.stop());
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _poll?.cancel();
    if (state != AppLifecycleState.resumed && _liveCall.joined) {
      unawaited(_liveCall.end());
    }
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _poll = Timer.periodic(
        Duration(seconds: _statePollSeconds),
        (_) => _refresh(),
      );
    }
  }

  Future<void> _refresh() async {
    if (_loading || _busy) return;
    _loading = true;
    try {
      final data = await widget.store.hearing(widget.caseId);
      await _apply(data);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _apply(Map<String, dynamic> data) async {
    final phaseChanged = _case?['phase'] != data['phase'];
    await _configureTherapistVoice(data['therapyLanguage'] as String? ?? 'en');
    for (final raw in data['evidence'] as List) {
      final e = raw as Map;
      final id = e['photoId'] as String;
      if (!_photos.containsKey(id)) {
        _photos[id] = await widget.store.photoPath(id);
      }
    }
    for (final id in (data['portraits'] as List? ?? []).whereType<String>()) {
      _photos[id] ??= await widget.store.photoPath(id);
    }
    if (data['scenePhotoId'] != null) {
      final id = data['scenePhotoId'] as String;
      _photos[id] ??= await widget.store.photoPath(id);
    }
    if (!mounted) return;
    final entered =
        (data['phase'] as int) > 0 ||
        (data['joined'] as List).contains(widget.store.uid);
    if (entered != _inCourtMode) {
      _inCourtMode = entered;
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]),
      );
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    setState(() {
      _case = data;
      if (data['serverNow'] is num) {
        _clockOffset =
            (data['serverNow'] as num).toDouble() -
            DateTime.now().millisecondsSinceEpoch / 1000;
      }
      _error = null;
      if (phaseChanged) {
        _text.clear();
        if (_listening) {
          _listening = false;
          unawaited(_speech.stop());
        }
      }
    });
    if (data['phase'] == 18) {
      _therapistSpeaking = false;
      _speechGeneration++;
      unawaited(_therapistVoice.stop());
      if (_liveCall.status != 'not_started' && _liveCall.status != 'ended') {
        unawaited(_liveCall.end());
      }
      _syncCallTurn();
    } else {
      _syncCallTurn();
      _maybeSpeakTherapist(data, data['phase'] as int);
    }
    _queueFacilitator(data);
  }

  Future<void> _configureTherapistVoice(String language) async {
    final locale = switch (language) {
      'id' => 'id-ID',
      'ms' => 'ms-MY',
      'hi' => 'hi-IN',
      'fil' => 'fil-PH',
      _ => 'en-US',
    };
    if (_configuredVoiceLocale == locale) return;
    try {
      await _therapistVoice.setLanguage(locale);
      await _therapistVoice.setSpeechRate(0.47);
      await _therapistVoice.awaitSpeakCompletion(true);
      _configuredVoiceLocale = locale;
    } catch (_) {}
  }

  void _syncCallTurn() {
    final current = _case;
    if (current == null) {
      _liveCall.setTurnAllowed(false);
      return;
    }
    final phase = current['phase'] as int;
    final people = current['people'] as List;
    final role = people.indexOf(widget.store.uid);
    final deadline = current['deadline'];
    final hasTime =
        deadline is! num ||
        deadline > DateTime.now().millisecondsSinceEpoch / 1000 + _clockOffset;
    final consent = (current['aiConsent'] as List? ?? const []).length == 2;
    final aiReady =
        consent &&
        current['openingResponseDone'] == true &&
        current['facilitatorPending'] != true &&
        current['lease'] == null &&
        (current['playbackPending'] as List? ?? const []).isEmpty;
    _liveCall.setTurnAllowed(
      _liveCall.connected &&
          aiReady &&
          _turns[phase] == role &&
          hasTime &&
          phase < 18 &&
          !_therapistSpeaking &&
          !_listening,
    );
    final track = _liveCall.microphoneTrackId;
    final validTurn =
        _liveCall.connected &&
        aiReady &&
        _turns[phase] == role &&
        !_therapistSpeaking &&
        !_listening;
    if (validTurn && hasTime && !_liveCall.muted && track != null && !_busy) {
      final remaining = deadline is num
          ? (deadline -
                    DateTime.now().millisecondsSinceEpoch / 1000 -
                    _clockOffset)
                .ceil()
          : 120;
      unawaited(_voice.start(current['version'] as int, track, remaining));
    } else if (_voice.active && !_voice.finishing) {
      if (validTurn && !hasTime) {
        unawaited(_voice.finish());
      } else {
        unawaited(_voice.cancel());
        _voice.allowRetry();
      }
    }
  }

  void _onCallChanged() {
    if (!mounted) return;
    final nextPollSeconds = _liveCall.joined && _liveCall.status != 'failed'
        ? 2
        : 5;
    if (nextPollSeconds != _statePollSeconds) {
      _statePollSeconds = nextPollSeconds;
      _poll?.cancel();
      _poll = Timer.periodic(
        Duration(seconds: _statePollSeconds),
        (_) => _refresh(),
      );
    }
    _syncCallTurn();
    final current = _case;
    if (_liveCall.connected && current != null) {
      _maybeSpeakTherapist(current, current['phase'] as int);
    } else if (_liveCall.status == 'ended' || _liveCall.status == 'failed') {
      _lastSpokenPhase = null;
      _lastSpokenResponseId = null;
      _therapistSpeaking = false;
      _speechGeneration++;
      unawaited(_therapistVoice.stop());
    }
    setState(() {});
  }

  String? _therapistLine(Map<String, dynamic> data, int phase) {
    if (phase == 10) {
      final questions = List<String>.from(
        data['judgeQuestions'] as List? ?? const [],
      );
      final names = List<String>.from(data['names'] as List? ?? const []);
      if (questions.length != 2 || names.length != 2) return null;
      return <String>[
        names[0],
        ': ',
        questions[0],
        ' ',
        names[1],
        ': ',
        questions[1],
      ].join();
    }
    if (phase == 13 || phase == 17) {
      final ruling = data['ruling'];
      if (ruling is! Map) return null;
      final plan = ruling['proposedRemedy'] as String? ?? '';
      final reflection = ruling['reasoning'] as String? ?? '';
      return [plan, reflection].join(' ');
    }
    return null;
  }

  void _maybeSpeakTherapist(Map<String, dynamic> data, int phase) {
    if (!_liveCall.connected) return;
    final responses = data['facilitatorResponses'] as List? ?? const [];
    final latest = responses.isEmpty ? null : responses.last as Map;
    final latestId = latest?['id'] as String?;
    final responseIsNew = latestId != null && latestId != _lastSpokenResponseId;
    if (!responseIsNew && (!_liveCall.connected || _lastSpokenPhase == phase)) {
      return;
    }
    final line = responseIsNew
        ? latest!['message'] as String?
        : _therapistLine(data, phase);
    if (line == null || line.trim().isEmpty) return;
    if (responseIsNew) {
      _lastSpokenResponseId = latestId;
    } else {
      _lastSpokenPhase = phase;
    }
    final generation = ++_speechGeneration;
    _therapistSpeaking = true;
    _syncCallTurn();
    setState(() {});
    unawaited(() async {
      try {
        await _therapistVoice.stop();
        await _therapistVoice.speak(
          line.length > 900
              ? line.substring(0, 900).replaceRange(900, 900, '…')
              : line,
        );
      } catch (_) {
      } finally {
        if (generation == _speechGeneration) {
          _therapistSpeaking = false;
          final playbackId = data['playbackId'] as String?;
          if (playbackId != null) await _acknowledgePlayback(playbackId);
          _syncCallTurn();
          if (mounted) setState(() {});
        }
      }
    }());
  }

  Future<void> _acknowledgePlayback(String id) async {
    if (_playbackAcknowledged == id) return;
    try {
      final state = await widget.store.hearing(
        widget.caseId,
        body: {'operation': 'speech_done', 'playbackId': id},
      );
      _playbackAcknowledged = id;
      if (mounted) await _apply(state);
    } catch (_) {
      if (mounted)
        setState(
          () => _voiceStatus =
              'Tap Continue after the spoken response to resume.',
        );
    }
  }

  Future<void> _startVoiceCall() async {
    try {
      await _liveCall.join();
      _syncCallTurn();
      final current = _case;
      if (_liveCall.connected && current != null) {
        _maybeSpeakTherapist(current, current['phase'] as int);
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => _error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Widget _liveCallPanel({
    required bool both,
    required int phase,
    required int role,
  }) {
    if (!both || phase >= 18) return const SizedBox.shrink();
    final canSpeak = _callTurnAllowed(role, phase);
    final title = _liveCall.status == 'ended'
        ? 'The voice call has ended'
        : _liveCall.connected
        ? (_liveCall.muted
              ? 'Call connected · microphone muted'
              : 'You’re live')
        : _liveCall.status == 'failed'
        ? 'Could not connect'
        : _liveCall.joined
        ? tr('Waiting for your partner to connect…')
        : 'Join the three-way voice session';
    final detail = _liveCall.connected
        ? 'You hear your partner live. Each phone also reads Metherapy’s replies aloud.'
        : _liveCall.error ??
              'By joining, you agree that your speaking-turn audio is streamed through Closer to Meta for transcription. Transcripts, the topic and optional photos are shared with Meta AI. Closer does not save raw audio. Both phones read replies aloud. A 3-second pause after speech ends your turn.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .76),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .9)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _liveCall.connected ? Icons.call_rounded : Icons.call_outlined,
                color: const Color(0xFFB85842),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF633322),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: Color(0xFF80665D),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!_liveCall.joined || _liveCall.status == 'failed')
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (_liveCall.status == 'failed') {
                            await _liveCall.end();
                          }
                          await _startVoiceCall();
                        },
                  icon: const Icon(Icons.call_rounded),
                  label: Text(
                    _liveCall.status == 'failed' ? 'Try again' : 'Join call',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB85842),
                    foregroundColor: Colors.white,
                  ),
                )
              else if (_liveCall.connected)
                FilledButton.tonalIcon(
                  onPressed: canSpeak ? _liveCall.toggleMute : null,
                  icon: Icon(
                    _liveCall.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  ),
                  label: Text(
                    _liveCall.muted ? tr('Mic muted') : tr('Mute mic'),
                  ),
                ),
              if (_liveCall.joined)
                OutlinedButton.icon(
                  onPressed: _liveCall.end,
                  icon: const Icon(Icons.call_end_rounded),
                  label: Text(tr('Leave call')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _callTurnAllowed(int role, int phase) {
    final current = _case;
    final deadline = current?['deadline'];
    final hasTime =
        deadline is! num ||
        deadline > DateTime.now().millisecondsSinceEpoch / 1000 + _clockOffset;
    final consent = (current?['aiConsent'] as List? ?? const []).length == 2;
    final aiReady =
        consent &&
        current?['openingResponseDone'] == true &&
        current?['facilitatorPending'] != true &&
        current?['lease'] == null;
    return _liveCall.connected &&
        aiReady &&
        _turns[phase] == role &&
        hasTime &&
        phase < 18 &&
        !_therapistSpeaking &&
        !_listening;
  }

  Widget _metherapyConsentCard({required bool hasConsented}) =>
      const SizedBox.shrink();

  Widget _therapistResponseCard(Map<String, dynamic> data) {
    final responses = data['facilitatorResponses'] as List? ?? const [];
    if (responses.isEmpty) return const SizedBox.shrink();
    final last = responses.last as Map;
    // The opening welcome is already spoken by the AI orb. Keep the call
    // canvas clear until the therapist has a response to the couple's turns.
    if (last['sourcePhase'] == null) return const SizedBox.shrink();
    final message = last['message'] as String? ?? '';
    if (message.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD5C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                color: Color(0xFF168FE0),
                size: 19,
              ),
              SizedBox(width: 7),
              Text(
                tr('Metherapy · Meta AI'),
                style: TextStyle(
                  color: Color(0xFF633322),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF44302A),
              height: 1.4,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Spoken aloud by your phone'),
            style: TextStyle(color: Color(0xFF80665D), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _facilitatorStatusCard(Map<String, dynamic> data) {
    final lease = data['lease'];
    final waiting =
        lease is Map &&
        lease['until'] is num &&
        (lease['until'] as num) >
            DateTime.now().millisecondsSinceEpoch / 1000 + _clockOffset;
    final retryReady =
        _facilitatorAttemptedVersion == data['version'] && !waiting && !_busy;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          if (waiting || _busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF168FE0),
              ),
            )
          else
            const Icon(Icons.graphic_eq_rounded, color: Color(0xFF168FE0)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              waiting || _busy
                  ? (data['openingResponseDone'] == true
                        ? 'Metherapy is listening to the submitted turn and preparing a response…'
                        : 'Metherapy is preparing a welcome for both of you…')
                  : retryReady
                  ? (_error ?? 'Metherapy could not finish. Tap to try again.')
                  : 'Metherapy is preparing a welcome for both of you…',
              style: const TextStyle(
                color: Color(0xFF633322),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          if (!waiting && !_aiAvailable)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _ensureAiConnection() &&
                          mounted &&
                          _case != null) {
                        _queueFacilitator(_case!);
                      }
                    },
              child: Text(tr('Connect')),
            )
          else if (retryReady)
            IconButton(
              tooltip: tr('Retry Metherapy'),
              onPressed: _busy ? null : () => _requestFacilitator(retry: true),
              icon: const Icon(Icons.refresh_rounded),
              color: const Color(0xFFB85842),
            ),
        ],
      ),
    );
  }

  Future<void> _act(String operation, {Map<String, dynamic>? extra}) async {
    if ((_busy && operation != 'end') || _case == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.store.hearing(
        widget.caseId,
        body: {'operation': operation, 'version': _case!['version'], ...?extra},
      );
      await _apply(data);
      await widget.store.refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _aiAvailable =>
      widget.store.user != null || BackendAccess.instance.connected;

  Future<bool> _ensureAiConnection() async {
    if (widget.store.user != null) return true;
    if (widget.store.roomSession != null) {
      try {
        await BackendAccess.instance.connectRoom(widget.store.roomSession!);
        return true;
      } catch (_) {
        if (mounted)
          setState(() => _error = 'AI access is unavailable. Please retry.');
      }
    }
    return false;
  }

  void _queueFacilitator(Map<String, dynamic> data) {
    final lease = data['lease'];
    final leaseActive =
        lease is Map &&
        lease['until'] is num &&
        (lease['until'] as num) >
            DateTime.now().millisecondsSinceEpoch / 1000 + _clockOffset;
    if (!_liveCall.connected ||
        !_aiAvailable ||
        (data['aiConsent'] as List? ?? const []).length != 2 ||
        data['facilitatorPending'] != true ||
        leaseActive) {
      return;
    }
    final version = data['version'] as int?;
    if (version == null ||
        version == _facilitatorAttemptedVersion ||
        _facilitatorRequestRunning) {
      return;
    }
    _facilitatorTimer?.cancel();
    _facilitatorTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_busy || _loading) {
        _queueFacilitator(_case ?? data);
        return;
      }
      unawaited(_requestFacilitator());
    });
  }

  Future<void> _requestFacilitator({bool retry = false}) async {
    final current = _case;
    if (!_liveCall.connected || current == null || _facilitatorRequestRunning)
      return;
    final version = current['version'] as int;
    if (retry) _facilitatorAttemptedVersion = null;
    if (_facilitatorAttemptedVersion == version) return;
    if (!_aiAvailable && !await _ensureAiConnection()) {
      return;
    }
    if (!mounted) return;
    _facilitatorAttemptedVersion = version;
    _facilitatorRequestRunning = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final operation = current['openingResponseDone'] == true
          ? 'facilitate'
          : 'opening';
      final data = await widget.store.hearing(
        widget.caseId,
        body: {'operation': operation, 'version': version},
      );
      await _apply(data);
      await widget.store.refresh();
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (mounted && !message.toLowerCase().contains('already preparing')) {
        setState(() => _error = message);
      }
    } finally {
      _facilitatorRequestRunning = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 65,
    );
    if (image == null || !mounted) return;
    if (await image.length() > 1000000) {
      if (mounted) {
        setState(() => _error = 'Choose an evidence photo smaller than 1 MB.');
      }
      return;
    }
    if (!mounted) return;
    final caption = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Add a photo for context')),
        content: TextField(
          controller: _caption,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: tr('What should the facilitator know about this photo?'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _caption.text.trim()),
            child: Text(tr('Share exhibit')),
          ),
        ],
      ),
    );
    if (caption == null || caption.isEmpty || !mounted) return;
    setState(() => _busy = true);
    String? id;
    try {
      id = await widget.store.upload(image.path);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not upload this exhibit.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (id != null) {
      await _act('evidence', extra: {'photoId': id, 'caption': caption});
    }
    _caption.clear();
  }

  Future<void> _openEvidence(Map exhibit) async {
    final photoId = exhibit['photoId'] as String?;
    final path = photoId == null ? null : _photos[photoId];
    if (path == null || !mounted) return;
    final judge = JudgeService();
    try {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => EvidenceHighlights(
            path: path,
            caption: exhibit['caption'] as String? ?? '',
            judge: judge,
          ),
        ),
      );
    } finally {
      judge.close();
    }
  }

  Future<void> _pauseMenu() async {
    final ended = _case?['phase'] == 18;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Metherapy session')),
        content: Text(
          ended ? 'This session has ended and can’t be re-entered.' : 'Leaving this screen keeps the session open. End it for both of you to close it permanently; an ended session can’t be re-entered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'stay'),
            child: Text(tr('Stay in session')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'leave'),
            child: Text(tr('Leave screen')),
          ),
          if (!ended)
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, 'end'),
              child: Text(tr('End for both')),
            ),
        ],
      ),
    );
    if (action == 'end') {
      await _act('end');
      return;
    }
    if (action == 'leave' && mounted) {
      if (widget.onLobby != null) {
        widget.onLobby!();
      } else {
        await Navigator.of(context).maybePop();
      }
    }
  }

  Future<void> _toggleListening(bool canSpeak) async {
    if (!canSpeak || _busy) return;
    if (_listening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _listening = false);
        _syncCallTurn();
        _callDetailsRebuild?.call();
      }
      return;
    }
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _listening = false);
              _syncCallTurn();
              _callDetailsRebuild?.call();
            }
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _listening = false;
              _error = 'Speech input stopped. You can type your turn instead.';
            });
            _syncCallTurn();
            _callDetailsRebuild?.call();
          }
        },
      );
      if (!available || !mounted) {
        if (mounted) {
          setState(
            () => _error =
                'Speech input is unavailable. You can type your turn instead.',
          );
        }
        return;
      }
      _text.clear();
      setState(() {
        _listening = true;
        _error = null;
      });
      _syncCallTurn();
      _callDetailsRebuild?.call();
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() => _text.text = result.recognizedWords);
          _callDetailsRebuild?.call();
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: Duration(seconds: 60),
          pauseFor: Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error =
              'Speech input is unavailable. You can type your turn instead.';
        });
      }
    }
  }

  Widget _metherapyNameBubble({double fontSize = 15}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .26),
      border: Border.all(color: Colors.white.withValues(alpha: .58)),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.white.withValues(alpha: .12),
          blurRadius: 12,
          spreadRadius: 1,
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr('Metherapy'),
          style: TextStyle(
            color: Color(0xFF544445),
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
          ),
        ),
        const SizedBox(width: 7),
        const Icon(Icons.verified_rounded, color: Color(0xFF20A9F4), size: 20),
      ],
    ),
  );

  Widget _partnerOrb({
    required int index,
    required int role,
    required List<String> names,
    required int activeSpeaker,
    required bool muted,
    required double diameter,
  }) {
    final path = index == role
        ? widget.store.avatarPath
        : widget.store.partnerAvatarPath;
    final active = activeSpeaker == index;
    return SizedBox(
      width: diameter + 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: diameter + 16),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .26),
              border: Border.all(color: Colors.white.withValues(alpha: .55)),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: .10),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Text(
              names[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF544445),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 9),
          _PulseAvatar(
            active: active,
            size: diameter,
            blue: false,
            child: ClipOval(
              child: path == null
                  ? Container(
                      color: const Color(0xFFC28F88),
                      alignment: Alignment.center,
                      child: Text(
                        names[index].trim().isEmpty
                            ? '?'
                            : names[index]
                                  .trim()
                                  .characters
                                  .first
                                  .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 44,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : photoImage(path, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                size: 14,
                color: muted
                    ? const Color(0xFF9A786C)
                    : const Color(0xFFE97859),
              ),
              const SizedBox(width: 4),
              Text(
                muted ? tr('Mic muted') : tr('Your turn'),
                style: TextStyle(
                  fontSize: 12,
                  color: muted
                      ? const Color(0xFF80665D)
                      : const Color(0xFFB85842),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gameCourt(
    BuildContext context,
    Map<String, dynamic> c, {
    required int phase,
    required int role,
    required bool both,
    required int seconds,
    required bool myTurn,
    required Map? ruling,
  }) {
    if (_liveCall.connected) {
      return _connectedCallView(
        c,
        phase: phase,
        role: role,
        both: both,
        seconds: seconds,
        myTurn: myTurn,
        ruling: ruling,
      );
    }
    return _sessionRoomView(
      context,
      c,
      phase: phase,
      role: role,
      both: both,
      seconds: seconds,
      myTurn: myTurn,
      ruling: ruling,
    );
  }

  Widget _callParticipant({
    required int index,
    required int role,
    required List<String> names,
    required int activeSpeaker,
    required double diameter,
    required Color badgeColor,
  }) {
    final path = index == role
        ? widget.store.avatarPath
        : widget.store.partnerAvatarPath;
    final active = activeSpeaker == index;
    return SizedBox(
      width: diameter + 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: diameter + 20),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .26),
              border: Border.all(color: Colors.white.withValues(alpha: .48)),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    names[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF544445),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.verified_rounded, color: badgeColor, size: 19),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _PulseAvatar(
            active: active,
            size: diameter,
            blue: false,
            child: ClipOval(
              child: path == null
                  ? Container(
                      color: const Color(0xFFC28F88),
                      alignment: Alignment.center,
                      child: Text(
                        names[index].trim().isEmpty
                            ? '?'
                            : names[index]
                                  .trim()
                                  .characters
                                  .first
                                  .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 44,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : photoImage(path, fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectedCallView(
    Map<String, dynamic> c, {
    required int phase,
    required int role,
    required bool both,
    required int seconds,
    required bool myTurn,
    required Map? ruling,
  }) {
    final names = List<String>.from(c['names'] as List);
    final aiConsent = c['aiConsent'] as List? ?? const [];
    final bothConsented = aiConsent.length == 2;
    final myConsent = aiConsent.contains(widget.store.uid);
    final activeSpeaker = _therapistSpeaking || c['facilitatorPending'] == true
        ? 2
        : _turns.containsKey(phase)
        ? _turns[phase]!
        : 2;
    final callCanSpeak = _callTurnAllowed(role, phase);
    final prompt = tr(_titles[phase]);
    final callStatus = _therapistSpeaking
        ? tr('Metherapy is speaking')
        : c['facilitatorPending'] == true
        ? tr('Metherapy is preparing a response')
        : _turns.containsKey(phase)
        ? (myTurn
              ? tr('Your turn · tap to respond')
              : trParams('{name} is speaking', {'name': names[_turns[phase]!]}))
        : (phase == 18 ? tr('Session complete') : prompt);

    return Scaffold(
      backgroundColor: const Color(0xFFFCF8F6),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _MetherapyBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final aiSize = (constraints.maxWidth * .48)
                    .clamp(180.0, 300.0)
                    .toDouble();
                final participantSize = (constraints.maxWidth * .32)
                    .clamp(112.0, 220.0)
                    .toDouble();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              SizedBox(height: constraints.maxHeight * .025),
                              _metherapyNameBubble(fontSize: 17),
                              const SizedBox(height: 9),
                              _PulseAvatar(
                                active: activeSpeaker == 2,
                                size: aiSize,
                                blue: true,
                                child: Center(
                                  child: Text(
                                    tr('AI'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 40,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(height: constraints.maxHeight * .035),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _callParticipant(
                                    index: 0,
                                    role: role,
                                    names: names,
                                    activeSpeaker: activeSpeaker,
                                    diameter: participantSize,
                                    badgeColor: const Color(0xFF8E62F5),
                                  ),
                                  _callParticipant(
                                    index: 1,
                                    role: role,
                                    names: names,
                                    activeSpeaker: activeSpeaker,
                                    diameter: participantSize,
                                    badgeColor: const Color(0xFFEC5B87),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              if (both && !bothConsented)
                                _metherapyConsentCard(hasConsented: myConsent)
                              else if (both && c['facilitatorPending'] == true)
                                _facilitatorStatusCard(c)
                              else if (ruling != null)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .65),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    ruling['proposedRemedy'] as String? ?? '',
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF633322),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (both && bothConsented)
                                TextButton(
                                  onPressed: () => _openCallDetails(
                                    c,
                                    phase: phase,
                                    role: role,
                                    seconds: seconds,
                                    myTurn: myTurn,
                                    ruling: ruling,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF6E3929),
                                  ),
                                  child: Text(
                                    callStatus,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                )
                              else if (!both)
                                Text(
                                  trParams(
                                    'Waiting for {name} to join this session.',
                                    {'name': names[role == 0 ? 1 : 0]},
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF764936),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_voiceStatus.isNotEmpty)
                        Text(
                          _voiceStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF66565B),
                            fontSize: 12,
                          ),
                        ),
                      if (myTurn &&
                          !_voice.active &&
                          !_voice.finishing &&
                          _liveCall.connected)
                        TextButton(
                          onPressed: () {
                            _voice.allowRetry();
                            _syncCallTurn();
                          },
                          child: const Text('Retry voice'),
                        ),
                      if ((c['playbackPending'] as List? ?? const []).contains(
                            widget.store.uid,
                          ) &&
                          !_therapistSpeaking)
                        TextButton(
                          onPressed: () =>
                              _acknowledgePlayback(c['playbackId'] as String),
                          child: const Text('Continue after spoken response'),
                        ),
                      if (_liveCall.connected &&
                          myTurn &&
                          _turns.containsKey(phase) &&
                          c['facilitatorPending'] != true)
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (_voice.active) {
                                    await _voice.finish();
                                  } else if (_text.text.trim().isNotEmpty) {
                                    await _act(
                                      'turn',
                                      extra: {'text': _text.text.trim()},
                                    );
                                  } else {
                                    _voice.allowRetry();
                                    _syncCallTurn();
                                  }
                                },
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text('End turn'),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _roundCallButton(
                              icon: _liveCall.muted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_rounded,
                              enabled: callCanSpeak,
                              tooltip: _liveCall.muted
                                  ? tr('Turn on microphone')
                                  : tr('Mute microphone'),
                              onPressed: _liveCall.toggleMute,
                            ),
                            if (both &&
                                bothConsented &&
                                _turns.containsKey(phase))
                              TextButton.icon(
                                onPressed: () => _openCallDetails(
                                  c,
                                  phase: phase,
                                  role: role,
                                  seconds: seconds,
                                  myTurn: myTurn,
                                  ruling: ruling,
                                ),
                                icon: const Icon(Icons.edit_note_rounded),
                                label: Text(
                                  myTurn ? 'Respond' : 'Session details',
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF6E3929),
                                ),
                              )
                            else
                              const SizedBox(width: 112),
                            _roundCallButton(
                              icon: Icons.close_rounded,
                              enabled: true,
                              tooltip: tr('Leave session'),
                              onPressed: _pauseMenu,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundCallButton({
    required IconData icon,
    required bool enabled,
    required String tooltip,
    required VoidCallback onPressed,
  }) => Container(
    width: 78,
    height: 78,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: enabled ? .24 : .10),
      shape: BoxShape.circle,
      border: Border.all(
        color: Colors.white.withValues(alpha: .45),
        width: 1.5,
      ),
    ),
    child: IconButton(
      onPressed: enabled ? onPressed : null,
      tooltip: tooltip,
      icon: Icon(
        icon,
        color: enabled ? Colors.white : Colors.white54,
        size: 31,
      ),
    ),
  );

  Future<void> _openCallDetails(
    Map<String, dynamic> c, {
    required int phase,
    required int role,
    required int seconds,
    required bool myTurn,
    required Map? ruling,
  }) async {
    final names = List<String>.from(c['names'] as List);
    final topic = (c['topic'] as String? ?? '').trim();
    final aiConsent = c['aiConsent'] as List? ?? const [];
    final bothConsented = aiConsent.length == 2;
    final myConsent = aiConsent.contains(widget.store.uid);
    final canSubmit =
        _liveCall.connected &&
        bothConsented &&
        c['openingResponseDone'] == true &&
        c['facilitatorPending'] != true &&
        c['lease'] == null &&
        myTurn &&
        _turns.containsKey(phase) &&
        seconds > 0;
    final canContinue =
        _liveCall.connected &&
        bothConsented &&
        c['openingResponseDone'] == true &&
        c['facilitatorPending'] != true &&
        myTurn &&
        _turns.containsKey(phase) &&
        seconds == 0;
    final canAddPhoto =
        bothConsented && (phase == 0 || (phase <= 8 && myTurn && seconds > 0));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final inset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            _callDetailsRebuild = () => setSheetState(() {});
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * .86,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF9F2),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + inset),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDAB8A9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          tr('Session details'),
                          style: TextStyle(
                            color: Color(0xFF633322),
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (topic.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE9DE),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('TODAY’S TOPIC'),
                                  style: TextStyle(
                                    color: Color(0xFF9C5B45),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  topic,
                                  style: const TextStyle(
                                    color: Color(0xFF603525),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!bothConsented) ...[
                          const SizedBox(height: 12),
                          _metherapyConsentCard(hasConsented: myConsent),
                        ] else if (c['facilitatorPending'] == true) ...[
                          const SizedBox(height: 12),
                          _facilitatorStatusCard(c),
                        ] else if (bothConsented) ...[
                          const SizedBox(height: 12),
                          _therapistResponseCard(c),
                        ],
                        if (ruling != null) ...[
                          Text(
                            tr('A possible shared next step'),
                            style: TextStyle(
                              color: Color(0xFFB85842),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            ruling['proposedRemedy'] as String? ?? '',
                            style: const TextStyle(color: Color(0xFF4B3329)),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (phase == 13 || phase == 17)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                onPressed:
                                    _busy ||
                                        (c['approved'] as List? ?? const [])
                                            .contains(widget.store.uid)
                                    ? null
                                    : () {
                                        Navigator.pop(sheetContext);
                                        _act('accept');
                                      },
                                child: Text(tr('Try this next step')),
                              ),
                              if (phase == 13 && role == 1)
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          Navigator.pop(sheetContext);
                                          _act('appeal');
                                        },
                                  child: Text(tr('Ask to revisit it')),
                                ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () {
                                        Navigator.pop(sheetContext);
                                        _act('decline');
                                      },
                                child: Text(tr('Not ready to agree')),
                              ),
                            ],
                          )
                        else if (phase == 18)
                          Text(
                            c['closedStatus'] == 'accepted'
                                ? 'You both chose this next step. This session has ended and can’t be re-entered.'
                                : '${_case?['endedByName'] ?? 'A partner'} ended this session. It can’t be re-entered.',
                            style: const TextStyle(color: Color(0xFF764936)),
                          )
                        else if (canContinue)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      Navigator.pop(sheetContext);
                                      _act('turn');
                                    },
                              child: Text(tr('Continue to the next turn')),
                            ),
                          )
                        else if (canSubmit) ...[
                          Text(
                            tr(_titles[phase]),
                            style: const TextStyle(
                              color: Color(0xFF633322),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _text,
                            minLines: 2,
                            maxLines: 4,
                            maxLength: phase == 0 ? 1000 : 2000,
                            onChanged: (_) => setSheetState(() {}),
                            decoration: InputDecoration(
                              hintText: _listening ? 'Listening…' : 'Share what you would like your partner to understand',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              IconButton.filledTonal(
                                onPressed: _busy
                                    ? null
                                    : () => _toggleListening(true),
                                tooltip: _listening
                                    ? 'Stop voice input'
                                    : 'Dictate a response',
                                icon: Icon(
                                  _listening
                                      ? Icons.stop_rounded
                                      : Icons.mic_rounded,
                                ),
                              ),
                              if (canAddPhoto)
                                TextButton.icon(
                                  onPressed: _busy ? null : _attach,
                                  icon: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                  ),
                                  label: Text(tr('Add photo')),
                                ),
                              FilledButton.icon(
                                onPressed: _busy || _text.text.trim().isEmpty
                                    ? null
                                    : () {
                                        final answer = _text.text.trim();
                                        Navigator.pop(sheetContext);
                                        _act('turn', extra: {'text': answer});
                                      },
                                icon: const Icon(Icons.arrow_upward_rounded),
                                label: Text(tr('Share turn')),
                              ),
                            ],
                          ),
                        ] else if (_turns.containsKey(phase))
                          Text(
                            trParams(
                              'Listening while {name} shares. Your mic is muted until your turn.',
                              {'name': names[_turns[phase]!]},
                            ),
                            style: const TextStyle(color: Color(0xFF764936)),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          tr(
                            'Metherapy is a supportive AI conversation guide, not a licensed therapist or clinical care.',
                          ),
                          style: TextStyle(
                            color: Color(0xFF80665D),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _callDetailsRebuild = null;
  }

  Widget _sessionRoomView(
    BuildContext context,
    Map<String, dynamic> c, {
    required int phase,
    required int role,
    required bool both,
    required int seconds,
    required bool myTurn,
    required Map? ruling,
  }) {
    final names = List<String>.from(c['names'] as List);
    final aiConsent = c['aiConsent'] as List? ?? const [];
    final bothConsented = aiConsent.length == 2;
    final myConsent = aiConsent.contains(widget.store.uid);
    final aiReady =
        bothConsented &&
        c['openingResponseDone'] == true &&
        c['facilitatorPending'] != true &&
        c['lease'] == null &&
        !_therapistSpeaking;
    final line = hearingLine(c);
    final activeSpeaker = !both
        ? 2
        : (_therapistSpeaking || c['facilitatorPending'] == true)
        ? 2
        : _turns.containsKey(phase)
        ? _turns[phase]!
        : (line.speaker < 2 ? line.speaker : 2);
    final canSubmit =
        _liveCall.connected &&
        both &&
        aiReady &&
        _turns.containsKey(phase) &&
        myTurn &&
        seconds > 0;
    final canContinue =
        _liveCall.connected &&
        both &&
        aiReady &&
        _turns.containsKey(phase) &&
        myTurn &&
        seconds == 0;
    final canSpeak = canSubmit && !_busy;
    final canAddPhoto =
        phase == 0 || (both && phase <= 8 && myTurn && seconds > 0);
    final timerActive = c['deadline'] != null && phase < 18;
    final timeText = timerActive
        ? (seconds ~/ 60).toString().padLeft(2, '0') +
              ':' +
              (seconds % 60).toString().padLeft(2, '0')
        : '—';
    final approved = (c['approved'] as List? ?? const []).contains(
      widget.store.uid,
    );
    final topic = (c['topic'] as String? ?? '').trim();
    final isMetaTurn = activeSpeaker == 2;

    return Scaffold(
      backgroundColor: const Color(0xFFFCF8F6),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _MetherapyBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final orb = (constraints.maxWidth * .39)
                    .clamp(118.0, 174.0)
                    .toDouble();
                final person = (constraints.maxWidth * .215)
                    .clamp(76.0, 100.0)
                    .toDouble();
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                onPressed: _pauseMenu,
                                tooltip: tr('Leave session'),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 28,
                                  color: Color(0xFF6E3929),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .30),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.timer_outlined,
                                      size: 17,
                                      color: Color(0xFF6E3929),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeText,
                                      style: const TextStyle(
                                        color: Color(0xFF6E3929),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (topic.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .37),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .40),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('TODAY’S TOPIC'),
                                    style: TextStyle(
                                      color: Color(0xFF9C5B45),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    topic,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF603525),
                                      fontSize: 15,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          _metherapyNameBubble(),
                          const SizedBox(height: 9),
                          _PulseAvatar(
                            active: isMetaTurn,
                            size: orb,
                            blue: true,
                            child: Center(
                              child: Text(
                                tr('AI'),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            (c['model'] as String?)?.contains('wonder') == true
                                ? 'Meta AI · Muse Wonder'
                                : 'Meta AI · Muse Spark',
                            style: TextStyle(
                              color: const Color(0xFF796D70),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _partnerOrb(
                                index: 0,
                                role: role,
                                names: names,
                                activeSpeaker: activeSpeaker,
                                muted:
                                    activeSpeaker != 0 ||
                                    (role == 0 && _liveCall.muted),
                                diameter: person,
                              ),
                              _partnerOrb(
                                index: 1,
                                role: role,
                                names: names,
                                activeSpeaker: activeSpeaker,
                                muted:
                                    activeSpeaker != 1 ||
                                    (role == 1 && _liveCall.muted),
                                diameter: person,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _liveCallPanel(both: both, phase: phase, role: role),
                          if (both && !bothConsented)
                            _metherapyConsentCard(hasConsented: myConsent)
                          else if (both && c['facilitatorPending'] == true)
                            _facilitatorStatusCard(c)
                          else if (both && bothConsented)
                            _therapistResponseCard(c),
                          if (!both)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                trParams(
                                  'Waiting for {name} to join this session.',
                                  {'name': names[role == 0 ? 1 : 0]},
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF764936),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          if (ruling != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF5E8),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('A possible shared next step'),
                                    style: TextStyle(
                                      color: Color(0xFFB85842),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    ruling['proposedRemedy'] as String? ?? '',
                                    style: const TextStyle(
                                      color: Color(0xFF4B3329),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    ruling['reasoning'] as String? ?? '',
                                    style: const TextStyle(
                                      color: Color(0xFF63483C),
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    trParams(
                                      'What may still be unclear: {text}',
                                      {
                                        'text':
                                            ruling['uncertainties']
                                                as String? ??
                                            '',
                                      },
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xFF80665D),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (canSubmit)
                            Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: TextField(
                                controller: _text,
                                enabled: canSpeak,
                                minLines: 2,
                                maxLines: 4,
                                maxLength: phase == 0 ? 1000 : 2000,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: _listening
                                      ? 'Listening… speak your turn'
                                      : 'Write your turn, or use the mic',
                                  counterText: '',
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: .78,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                          if (canAddPhoto && both)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _busy ? null : _attach,
                                  icon: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                  ),
                                  label: Text(
                                    tr('Add an optional photo for context'),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF8D4A37),
                                  ),
                                ),
                              ),
                            ),
                          if ((c['evidence'] as List? ?? const []).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: SizedBox(
                                height: 74,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    for (final raw in c['evidence'] as List)
                                      Builder(
                                        builder: (context) {
                                          final exhibit = raw as Map;
                                          final id =
                                              exhibit['photoId'] as String?;
                                          final path = id == null
                                              ? null
                                              : _photos[id];
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: InkWell(
                                              onTap: () =>
                                                  _openEvidence(exhibit),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: path == null
                                                    ? const SizedBox(
                                                        width: 74,
                                                        height: 74,
                                                        child: ColoredBox(
                                                          color: Color(
                                                            0xFFFFF3E8,
                                                          ),
                                                          child: Icon(
                                                            Icons
                                                                .image_outlined,
                                                          ),
                                                        ),
                                                      )
                                                    : photoImage(
                                                        path,
                                                        width: 74,
                                                        height: 74,
                                                        fit: BoxFit.cover,
                                                      ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (phase == 13 || phase == 17)
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: _busy || approved
                                      ? null
                                      : () => _act('accept'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFB25D46),
                                  ),
                                  child: Text(
                                    approved
                                        ? 'Plan saved · waiting'
                                        : 'Try this next step',
                                  ),
                                ),
                                if (phase == 13 && role == 1)
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _act('appeal'),
                                    child: Text(tr('Ask to revisit it')),
                                  ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _act('decline'),
                                  child: Text(tr('Not ready to agree')),
                                ),
                              ],
                            )
                          else if (phase == 18)
                            Text(
                              c['closedStatus'] == 'accepted'
                                  ? 'You both chose this next step. This session has ended and can’t be re-entered.'
                                  : '${_case?['endedByName'] ?? 'A partner'} ended this session. It can’t be re-entered.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF764936)),
                            )
                          else if (canContinue)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _busy ? null : () => _act('turn'),
                                child: Text(tr('Continue to the next turn')),
                              ),
                            )
                          else if (both && _turns.containsKey(phase) && !myTurn)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                trParams(
                                  'Listening while {name} shares. Your mic is muted until your turn.',
                                  {'name': names[_turns[phase]!]},
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF764936),
                                  fontSize: 13,
                                ),
                              ),
                            )
                          else if (canSubmit)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _busy || _text.text.trim().isEmpty
                                    ? null
                                    : () => _act(
                                        'turn',
                                        extra: {'text': _text.text.trim()},
                                      ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFB25D46),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: Text(tr('Share your turn')),
                              ),
                            ),
                          if (both && _turns.containsKey(phase))
                            Padding(
                              padding: const EdgeInsets.only(top: 9),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton.filled(
                                    onPressed: canSpeak
                                        ? () => _toggleListening(canSpeak)
                                        : null,
                                    tooltip: _listening
                                        ? 'Stop speaking'
                                        : 'Speak your turn',
                                    style: IconButton.styleFrom(
                                      backgroundColor: _listening
                                          ? const Color(0xFFBD6049)
                                          : Colors.white.withValues(alpha: .65),
                                      foregroundColor: _listening
                                          ? Colors.white
                                          : const Color(0xFF754333),
                                      disabledBackgroundColor: Colors.white
                                          .withValues(alpha: .3),
                                    ),
                                    icon: Icon(
                                      _listening
                                          ? Icons.stop_rounded
                                          : Icons.mic_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      canSpeak
                                          ? 'Your turn audio is transcribed by Meta and shared as session text.'
                                          : 'Your call microphone is muted until your turn.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFF764936),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (phase == 13 || phase == 17)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                trParams('Suggested next step: {text}', {
                                  'text':
                                      ruling?['proposedRemedy'] as String? ??
                                      '',
                                }),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF764936),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (_error != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7F1),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFF8E3427),
                                ),
                              ),
                            ),
                          if (_busy)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: LinearProgressIndicator(
                                color: Color(0xFFB25D46),
                                backgroundColor: Color(0x55FFFFFF),
                              ),
                            ),
                          const SizedBox(height: 14),
                          Text(
                            tr(
                              'Metherapy is a supportive AI conversation guide, not a licensed therapist. You can pause or leave at any time.',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF7B5547),
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _case;
    if (c == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFCF8F6),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _MetherapyBackdrop(),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulseAvatar(
                        active: true,
                        size: 132,
                        blue: true,
                        child: Center(
                          child: Text(
                            tr('AI'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        tr('Opening Metherapy session…'),
                        style: TextStyle(
                          color: Color(0xFF633322),
                          fontSize: 18,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF8E3427)),
                        ),
                        TextButton(
                          onPressed: _refresh,
                          child: Text(tr('Retry')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final phase = c['phase'] as int;
    final people = List<String>.from(c['people'] as List);
    final role = people.indexOf(widget.store.uid);
    final joined = (c['joined'] as List).contains(widget.store.uid);
    final both = (c['joined'] as List).length == 2;
    final deadline = c['deadline'] as num?;
    final seconds = deadline == null
        ? 0
        : (deadline -
                  (DateTime.now().millisecondsSinceEpoch / 1000 + _clockOffset))
              .ceil()
              .clamp(0, 120);
    final myTurn = _turns[phase] == role;
    final ruling = c['ruling'] as Map?;
    if (joined || phase > 0) {
      return _gameCourt(
        context,
        c,
        phase: phase,
        role: role,
        both: both,
        seconds: seconds,
        myTurn: myTurn,
        ruling: ruling,
      );
    }

    final names = List<String>.from(c['names'] as List);
    final topic = (c['topic'] as String? ?? '').trim();
    return Scaffold(
      backgroundColor: const Color(0xFFFCF8F6),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _MetherapyBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final orb = (constraints.maxWidth * .38)
                    .clamp(118.0, 164.0)
                    .toDouble();
                final person = (constraints.maxWidth * .21)
                    .clamp(74.0, 94.0)
                    .toDouble();
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: IconButton(
                              onPressed: _pauseMenu,
                              tooltip: tr('Session options'),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Color(0xFF6E3929),
                              ),
                            ),
                          ),
                          Text(
                            tr('A little space to hear each other.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF633322),
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 13),
                          _metherapyNameBubble(),
                          const SizedBox(height: 9),
                          _PulseAvatar(
                            active: true,
                            size: orb,
                            blue: true,
                            child: Center(
                              child: Text(
                                tr('AI'),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            (c['model'] as String?)?.contains('wonder') == true
                                ? 'Meta AI · Muse Wonder'
                                : 'Meta AI · Muse Spark',
                            style: TextStyle(
                              color: const Color(0xFF796D70),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 17),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _partnerOrb(
                                index: 0,
                                role: role,
                                names: names,
                                activeSpeaker: 2,
                                muted: true,
                                diameter: person,
                              ),
                              _partnerOrb(
                                index: 1,
                                role: role,
                                names: names,
                                activeSpeaker: 2,
                                muted: true,
                                diameter: person,
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .55),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('WHAT YOU WANT TO TALK ABOUT'),
                                  style: TextStyle(
                                    color: Color(0xFF9C5B45),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  topic.isEmpty
                                      ? 'Your shared topic will appear here.'
                                      : topic,
                                  style: const TextStyle(
                                    color: Color(0xFF603525),
                                    fontSize: 15,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  tr(
                                    'This invitation topic is shared with the AI facilitator as session context.',
                                  ),
                                  style: TextStyle(
                                    color: Color(0xFF80665D),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (widget.roomInvite != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .44),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    tr('Invite your partner to this session'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF633322),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SelectableText(
                                    widget.roomInvite!,
                                    textAlign: TextAlign.center,
                                  ),
                                  TextButton.icon(
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: widget.roomInvite!),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  tr('Session invite copied'),
                                                ),
                                              ),
                                            );
                                      }
                                    },
                                    icon: const Icon(Icons.copy_rounded),
                                    label: Text(tr('Copy invite')),
                                  ),
                                ],
                              ),
                            ),
                          if (!both && joined)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                tr(
                                  'Your partner has been invited. You can start when they join.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF704033)),
                              ),
                            ),
                          if (!joined)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _busy ? null : () => _act('join'),
                                icon: const Icon(
                                  Icons.favorite_outline_rounded,
                                ),
                                label: Text(tr('Join Metherapy session')),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFB25D46),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                ),
                              ),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF8E3427),
                                ),
                              ),
                            ),
                          if (_busy)
                            const LinearProgressIndicator(
                              color: Color(0xFFB25D46),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            tr(
                              'Metherapy offers supportive conversation prompts. It is not a licensed therapist or clinical care.',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF7B5547),
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetherapyBackdrop extends StatelessWidget {
  const _MetherapyBackdrop();

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/metherapy_soft_waves.png',
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) => const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFC8AB), Color(0xFFFF9D96), Color(0xFFFFAF9D)],
        ),
      ),
    ),
  );
}

class _PulseAvatar extends StatefulWidget {
  const _PulseAvatar({
    required this.active,
    required this.size,
    required this.child,
    required this.blue,
  });

  final bool active;
  final double size;
  final Widget child;
  final bool blue;

  @override
  State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
      value: 0,
    );
    if (widget.active) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _pulse.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, child) {
      final scale = widget.active ? 1 + (_pulse.value * .055) : 1.0;
      final blue = widget.blue;
      final glow = widget.active ? (.18 + _pulse.value * .30) : .06;
      return Transform.scale(
        scale: scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: blue
                ? const RadialGradient(
                    center: Alignment(-.35, -.4),
                    radius: 1.05,
                    colors: [
                      Color(0xFFF8FFFF),
                      Color(0xFF9DE3FF),
                      Color(0xFF1597F2),
                    ],
                    stops: [0, .56, 1],
                  )
                : null,
            color: blue ? null : Colors.white.withValues(alpha: .82),
            border: Border.all(
              color: blue
                  ? Colors.white.withValues(alpha: .75)
                  : widget.active
                  ? const Color(0xFFFF855E)
                  : Colors.white.withValues(alpha: .86),
              width: widget.active ? 3.5 : 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (blue ? const Color(0xFF198FE8) : const Color(0xFFE97859))
                        .withValues(alpha: glow),
                blurRadius: widget.active ? 30 : 14,
                spreadRadius: widget.active ? 3 : 0,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}
