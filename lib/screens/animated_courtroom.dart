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
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/court/2d/court_stage.png',
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                _judgeRig(),
                _partnerRig(
                  bodyAsset: 'assets/court/2d/girl_body.png',
                  leftArmAsset: 'assets/court/2d/girl_arm_left.png',
                  rightArmAsset: 'assets/court/2d/girl_arm_right.png',
                  left: 106,
                  top: 215,
                  width: 452,
                  height: 468,
                  visibleHeight: 259,
                  voice: 0,
                  leftShoulder: const Offset(484 / 1233, 445 / 1276),
                  rightShoulder: const Offset(748 / 1233, 445 / 1276),
                ),
                _partnerRig(
                  bodyAsset: 'assets/court/2d/boy_body.png',
                  leftArmAsset: 'assets/court/2d/boy_arm_left.png',
                  rightArmAsset: 'assets/court/2d/boy_arm_right.png',
                  left: 1114,
                  top: 215,
                  width: 450,
                  height: 468,
                  visibleHeight: 259,
                  voice: 1,
                  leftShoulder: const Offset(420 / 1230, 432 / 1278),
                  rightShoulder: const Offset(807 / 1230, 432 / 1278),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _partnerRig({
    required String bodyAsset,
    required String leftArmAsset,
    required String rightArmAsset,
    required double left,
    required double top,
    required double width,
    required double height,
    required double visibleHeight,
    required int voice,
    required Offset leftShoulder,
    required Offset rightShoulder,
  }) {
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: visibleHeight,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final phase = _motion.value * math.pi * 2;
              final talking = _motionOn && _speaking && _line.speaker == voice;
              final wave = talking ? math.sin(phase * 7) * .16 : 0.0;
              final bob = math.sin(phase + voice) * (talking ? 2.2 : .8);
              return Transform.translate(
                offset: Offset(0, bob),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _rotatingLimb(leftArmAsset, leftShoulder, .52 + wave),
                      _rotatingLimb(rightArmAsset, rightShoulder, -.52 - wave),
                      Image.asset(bodyAsset, fit: BoxFit.fill),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _rotatingLimb(String asset, Offset pivot, double angle) {
    return Positioned.fill(
      child: Transform.rotate(
        alignment: Alignment(pivot.dx * 2 - 1, pivot.dy * 2 - 1),
        angle: angle,
        child: Image.asset(asset, fit: BoxFit.fill),
      ),
    );
  }

  Widget _judgeRig() {
    const width = 382.0;
    const height = 406.0;
    const visibleHeight = 278.0;
    return Positioned(
      left: 645,
      top: 65,
      width: width,
      height: visibleHeight,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final phase = _motion.value * math.pi * 2;
              final talking = _motionOn && _speaking && _line.speaker == 2;
              final swing = talking ? math.sin(phase * 8) * .22 : 0.0;
              final bob = math.sin(phase + 1) * (talking ? 1.8 : .55);
              return Transform.translate(
                offset: Offset(0, bob),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/court/2d/judge_body.png',
                          fit: BoxFit.fill,
                        ),
                      ),
                      Transform.rotate(
                        alignment: const Alignment(-.72, -.23),
                        angle: swing,
                        child: Image.asset(
                          'assets/court/2d/judge_gavel_hand.png',
                          fit: BoxFit.fill,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
