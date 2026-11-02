import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/cloud_couple_store.dart';
import '../services/court_audio.dart';
import '../services/court_performance.dart';

class AnimatedCourtroom extends StatefulWidget {
  const AnimatedCourtroom({
    super.key,
    required this.store,
    required this.hearing,
  });
  final CloudCoupleStore store;
  final Map<String, dynamic> hearing;
  @override
  State<AnimatedCourtroom> createState() => _AnimatedCourtroomState();
}

class _AnimatedCourtroomState extends State<AnimatedCourtroom>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  final _audio = CourtAudio();
  late CourtLine _line;
  Timer? _typing, _calloutTimer;
  String? _callout;
  String? _chatId;
  int _letters = 0;
  bool _speaking = false, _motionOn = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _line = hearingLine(widget.hearing);
    _letters = _line.text.length;
    _chatId = _latestChat()?['id'] as String?;
    widget.store.addListener(_chat);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motionOn = false;
    } else if (_motionOn && !_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedCourtroom oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = hearingLine(widget.hearing);
    final previous = hearingLine(oldWidget.hearing);
    final lineChanged = next.key != previous.key;
    final sound = _hearingSound(
      oldWidget.hearing,
      widget.hearing,
      next,
      lineChanged: lineChanged,
    );
    if (lineChanged) {
      _say(next, sound: sound);
    } else if (sound != null) {
      _audio.play(sound);
    }
  }

  CourtSound? _hearingSound(
    Map<String, dynamic> previous,
    Map<String, dynamic> current,
    CourtLine line, {
    required bool lineChanged,
  }) {
    final oldPhase = previous['phase'] as int?;
    final phase = current['phase'] as int?;
    if (oldPhase != phase && (phase == 13 || phase == 17 || phase == 18)) {
      if (phase == 13) return CourtSound.verdict;
      if (phase == 17) return CourtSound.appealDecision;
      return current['closedStatus'] == 'accepted'
          ? CourtSound.accepted
          : CourtSound.unresolved;
    }

    if (lineChanged) {
      final dialogueSound = _speechSound(line.text);
      if (dialogueSound != null) return dialogueSound;
    }

    if (oldPhase != phase) {
      if (phase == 1 || phase == 12 || phase == 16) {
        return CourtSound.courtroom;
      }
      if (phase != null &&
          ((phase >= 1 && phase <= 11) || phase == 14 || phase == 15)) {
        return CourtSound.turn;
      }
    }

    final previousEvidence = previous['evidence'] as List? ?? const [];
    final currentEvidence = current['evidence'] as List? ?? const [];
    if (currentEvidence.length > previousEvidence.length) {
      return CourtSound.evidence;
    }

    return null;
  }

  CourtSound? _speechSound(String text) {
    final normalized = text.toLowerCase();
    if (RegExp(r'\b(overruled|overrule)\b').hasMatch(normalized)) {
      return CourtSound.overruled;
    }
    if (RegExp(r'\b(sustained|upheld)\b').hasMatch(normalized)) {
      return CourtSound.sustained;
    }
    if (RegExp(r'\b(objection|i object)\b').hasMatch(normalized)) {
      return CourtSound.objection;
    }
    return null;
  }

  String? _calloutFor(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('overruled') || normalized.contains('overrule')) {
      return 'OVERRULED';
    }
    if (normalized.contains('sustained') || normalized.contains('upheld')) {
      return 'SUSTAINED';
    }
    if (normalized.contains('objection') || normalized.contains('i object')) {
      return 'OBJECTION!';
    }
    return null;
  }

  Map<String, dynamic>? _latestChat() {
    final messages = widget.store.messages.where(
      (m) => m['kind'] != 'court' && (m['text'] as String? ?? '').isNotEmpty,
    );
    return messages.isEmpty ? null : messages.last;
  }

  void _chat() {
    final latest = _latestChat();
    if (latest == null || latest['id'] == _chatId) return;
    _chatId = latest['id'] as String;
    final speaker = (widget.hearing['people'] as List).indexOf(
      latest['senderId'],
    );
    if (speaker >= 0) {
      _say(CourtLine('chat:$_chatId', speaker, latest['text'] as String));
    }
  }

  void _say(CourtLine line, {CourtSound? sound}) {
    _typing?.cancel();
    _calloutTimer?.cancel();
    if (!mounted) return;
    final callout = _calloutFor(line.text);
    setState(() {
      _line = line;
      _letters = _motionOn ? 0 : line.text.length;
      _speaking = _motionOn;
      _callout = callout;
    });
    if (callout != null) {
      _calloutTimer = Timer(const Duration(milliseconds: 1700), () {
        if (mounted) setState(() => _callout = null);
      });
    }
    final dialogueSound = sound ?? _speechSound(line.text);
    if (dialogueSound != null) {
      _audio.play(dialogueSound);
    } else {
      _audio.cue(line.speaker == 2);
    }
    if (!_motionOn) return;
    _typing = Timer.periodic(const Duration(milliseconds: 32), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _letters = math.min(_letters + 2, _line.text.length);
        if (_letters >= _line.text.length) {
          _speaking = false;
          timer.cancel();
        }
      });
      if (timer.tick % 4 == 0 && _speaking) _audio.blip(timer.tick);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_motionOn) _motion.repeat();
    } else {
      _motion.stop();
      _typing?.cancel();
      _speaking = false;
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_chat);
    WidgetsBinding.instance.removeObserver(this);
    _typing?.cancel();
    _calloutTimer?.cancel();
    _motion.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calloutColor = _callout == 'SUSTAINED'
        ? const Color(0xFF43865C)
        : const Color(0xFFCE332E);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : math.max(330.0, (constraints.maxWidth * .60).clamp(330.0, 660.0));
        return SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _courtStage2d(),
              if (_callout != null)
                Positioned(
                  top: 62,
                  right: 22,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Container(
                      key: ValueKey<String>(_callout!),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: calloutColor,
                        border: Border.all(
                          color: const Color(0xFFFFD66D),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x88000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        _callout!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _courtStage2d() {
    return ColoredBox(
      color: const Color(0xFF2D1B19),
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.center,
          child: SizedBox(
            width: 1672,
            height: 941,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (context, _) {
                final phase = _motion.value * math.pi * 2;
                final speaker = _motionOn && _speaking ? _line.speaker : -1;
                return Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Image.asset(
                      'assets/court/seated/courtroom.png',
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                    _handLayer(
                      asset: 'assets/court/seated/girl_gesture_hand.png',
                      pivot: const Offset(402, 485),
                      speaker: speaker,
                      currentSpeaker: 0,
                      phase: phase,
                    ),
                    _handLayer(
                      asset: 'assets/court/seated/girl_rest_hand.png',
                      pivot: const Offset(258, 549),
                      speaker: speaker,
                      currentSpeaker: 0,
                      phase: phase,
                      amplitude: 1.2,
                      angularAmplitude: .018,
                    ),
                    _handLayer(
                      asset: 'assets/court/seated/boy_gesture_hand.png',
                      pivot: const Offset(1277, 500),
                      speaker: speaker,
                      currentSpeaker: 1,
                      phase: phase,
                    ),
                    _handLayer(
                      asset: 'assets/court/seated/boy_rest_hand.png',
                      pivot: const Offset(1477, 543),
                      speaker: speaker,
                      currentSpeaker: 1,
                      phase: phase,
                    ),
                    _handLayer(
                      asset: 'assets/court/seated/judge_gavel_hand.png',
                      pivot: const Offset(670, 319),
                      speaker: speaker,
                      currentSpeaker: 2,
                      phase: phase,
                      amplitude: 3.2,
                      angularAmplitude: .075,
                    ),
                    _handLayer(
                      asset: 'assets/court/seated/judge_rest_hand.png',
                      pivot: const Offset(896, 331),
                      speaker: speaker,
                      currentSpeaker: 2,
                      phase: phase,
                      amplitude: 1.2,
                      angularAmplitude: .018,
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CourtMouthPainter(
                          phase: phase,
                          activeSpeaker: speaker,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _handLayer({
    required String asset,
    required Offset pivot,
    required int speaker,
    required int currentSpeaker,
    required double phase,
    double amplitude = 3.0,
    double angularAmplitude = .045,
  }) {
    final talking = speaker == currentSpeaker;
    final gesture = talking ? math.sin(phase * 8) : 0.0;
    return Positioned.fill(
      child: Transform.translate(
        offset: Offset(0, -gesture.abs() * amplitude),
        child: Transform.rotate(
          alignment: Alignment(pivot.dx / 1672 * 2 - 1, pivot.dy / 941 * 2 - 1),
          angle: gesture * angularAmplitude,
          child: Image.asset(asset, fit: BoxFit.fill),
        ),
      ),
    );
  }
}

class _CourtMouthPainter extends CustomPainter {
  const _CourtMouthPainter({required this.phase, required this.activeSpeaker});

  final double phase;
  final int activeSpeaker;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1672, size.height / 941);
    _partnerMouth(
      canvas,
      const Rect.fromLTWH(293, 455, 29, 29),
      const Color(0xFFFFBA96),
      const Color(0xFFF38A6C),
      0,
    );
    _partnerMouth(
      canvas,
      const Rect.fromLTWH(1349, 454, 35, 30),
      const Color(0xFFFFC397),
      const Color(0xFFF39475),
      1,
    );
    if (activeSpeaker == 2) {
      _mouth(
        canvas,
        const Rect.fromLTWH(840, 240, 31, 21),
        const Color(0xFFFFB38A),
        const Color(0xFFEE8467),
        true,
      );
    }
    canvas.restore();
  }

  void _partnerMouth(
    Canvas canvas,
    Rect rect,
    Color top,
    Color bottom,
    int speaker,
  ) {
    _mouth(canvas, rect, top, bottom, activeSpeaker == speaker);
  }

  void _mouth(Canvas canvas, Rect rect, Color top, Color bottom, bool talking) {
    final patch = Paint()
      ..shader = LinearGradient(colors: [top, bottom]).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      patch,
    );
    final flap = math.sin(phase * 28);
    final isOpen = talking && flap > -.2;
    if (isOpen) {
      final openHeight = 7.0 + math.max(0, flap) * 9.0;
      final mouth = Rect.fromCenter(
        center: Offset(rect.center.dx, rect.center.dy + 1),
        width: rect.width * .57,
        height: openHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(mouth, const Radius.circular(4)),
        Paint()..color = const Color(0xFF351015),
      );
      final tongue = Rect.fromLTWH(
        mouth.left + 2,
        mouth.bottom - 5,
        mouth.width - 4,
        3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(tongue, const Radius.circular(2)),
        Paint()..color = const Color(0xFFEF6670),
      );
    } else {
      final smile = Path()
        ..moveTo(rect.left + rect.width * .2, rect.center.dy)
        ..quadraticBezierTo(
          rect.center.dx,
          rect.center.dy + 5,
          rect.right - rect.width * .18,
          rect.center.dy - 1,
        );
      canvas.drawPath(
        smile,
        Paint()
          ..color = const Color(0xFF642A2A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CourtMouthPainter oldDelegate) =>
      phase != oldDelegate.phase || activeSpeaker != oldDelegate.activeSpeaker;
}
