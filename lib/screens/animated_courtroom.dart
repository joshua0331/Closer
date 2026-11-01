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
  Timer? _typing;
  String? _chatId;
  int _letters = 0;
  bool _speaking = false, _expanded = false, _motionOn = true;
  final _stageKey = GlobalKey();
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
    if (next.key != hearingLine(oldWidget.hearing).key) _say(next);
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

  void _say(CourtLine line) {
    _typing?.cancel();
    if (!mounted) return;
    setState(() {
      _line = line;
      _letters = _motionOn ? 0 : line.text.length;
      _speaking = _motionOn;
    });
    _audio.cue(line.speaker == 2);
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

  void _skip() {
    _typing?.cancel();
    setState(() {
      _letters = _line.text.length;
      _speaking = false;
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
    _motion.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = List<String>.from(widget.hearing['names'] as List);
    final speaker = _line.speaker == 2
        ? 'Judge · ${(widget.hearing['phase'] as int) >= 14 ? 'Muse Wonder' : 'Muse Spark'}'
        : names[_line.speaker];
    return Column(
      key: _stageKey,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF35231F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(
            children: [
              const Icon(Icons.circle, size: 9, color: Color(0xFFF5BD7A)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'COUPLE COURT · LIVE',
                  style: TextStyle(
                    color: Color(0xFFFFE7CB),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              IconButton(
                tooltip: _audio.enabled
                    ? 'Mute sound effects'
                    : 'Enable sound effects',
                color: Colors.white,
                onPressed: () {
                  setState(() => _audio.toggle());
                  if (_audio.enabled) _audio.cue(false);
                },
                icon: Icon(
                  _audio.enabled
                      ? Icons.volume_up_outlined
                      : Icons.volume_off_outlined,
                ),
              ),
              IconButton(
                tooltip: _motionOn ? 'Reduce motion' : 'Enable animation',
                color: Colors.white,
                onPressed: () {
                  setState(() => _motionOn = !_motionOn);
                  if (_motionOn) {
                    _motion.repeat();
                  } else {
                    _motion.stop();
                    _skip();
                  }
                },
                icon: Icon(
                  _motionOn
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
              ),
              IconButton(
                tooltip: _expanded ? 'Shrink courtroom' : 'Expand courtroom',
                color: Colors.white,
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  Scrollable.ensureVisible(
                    _stageKey.currentContext!,
                    alignment: 0,
                  );
                },
                icon: Icon(
                  _expanded ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, bounds) {
            final height = _expanded
                ? MediaQuery.sizeOf(context).height * .78
                : (bounds.maxWidth * .60).clamp(330.0, 660.0);
            return SizedBox(
              height: height + 185,
              width: double.infinity,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: height,
                      child: AnimatedBuilder(
                        animation: _motion,
                        builder: (context, _) => CustomPaint(
                          painter: _CourtPainter(
                            _motion.value * 12,
                            _line.speaker,
                            _speaking && _motionOn,
                            names,
                            (widget.hearing['phase'] as int) == 18,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xD935231F),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _speaking
                              ? '${names.length > _line.speaker ? names[_line.speaker] : 'Judge'} is speaking'
                              : 'Court is in session',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: height + 10,
                      left: 12,
                      right: 12,
                      child: Semantics(
                        liveRegion: true,
                        label: '$speaker: ${_line.text}',
                        child: Material(
                          color: const Color(0xFFFDF1DB),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _speaking ? _skip : () => _say(_line),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    speaker,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFA14D36),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: height < 400 ? 82 : 110,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Text(
                                        _line.text.substring(0, _letters),
                                        style: const TextStyle(
                                          color: Color(0xFF35231F),
                                          fontSize: 15,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _speaking
                                        ? 'Tap to show all'
                                        : 'Tap to replay dialogue',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF866B5D),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Sound effects start after you tap the speaker. Dialogue follows room messages and submitted testimony.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _CourtPainter extends CustomPainter {
  _CourtPainter(this.time, this.speaker, this.talking, this.names, this.closed);
  final double time;
  final int speaker;
  final bool talking, closed;
  final List<String> names;
  final _paint = Paint();
  void box(
    Canvas c,
    double x,
    double y,
    double w,
    double h,
    int color, [
    double radius = 0,
  ]) {
    _paint.color = Color(color);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(radius),
      ),
      _paint,
    );
  }

  void line(Canvas c, Offset a, Offset b, int color, double width) {
    c.drawLine(
      a,
      b,
      Paint()
        ..color = Color(color)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void text(
    Canvas c,
    String value,
    Rect rect, {
    double size = 17,
    int color = 0xFFFFE6C1,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.bold,
          color: Color(color),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);
    painter.paint(
      c,
      Offset(rect.left + (rect.width - painter.width) / 2, rect.top),
    );
  }

  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 1000, size.height / 660);
    final backdrop = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEAC9A1), Color(0xFFBB825B)],
      ).createShader(const Rect.fromLTWH(0, 0, 1000, 660));
    c.drawRect(const Rect.fromLTWH(0, 0, 1000, 660), backdrop);
    box(c, 0, 300, 1000, 360, 0xFF6F4633);
    final floor = Path()
      ..moveTo(260, 300)
      ..lineTo(740, 300)
      ..lineTo(1000, 660)
      ..lineTo(0, 660)
      ..close();
    c.drawPath(floor, Paint()..color = const Color(0xFFBB8153));
    for (var i = 0; i < 9; i++) {
      line(
        c,
        Offset(260 + i * 60, 300),
        Offset(-150 + i * 165, 660),
        0xFF9C6543,
        2,
      );
    }
    for (var y = 330.0; y < 660; y += 48) {
      line(c, Offset(0, y), Offset(1000, y), 0xFF9C6543, 2);
    }
    for (final x in [50.0, 830.0]) {
      box(c, x, 55, 120, 250, 0xFF80503C, 4);
      box(c, x + 10, 65, 100, 232, 0xFFBA8761, 3);
      box(c, x + 20, 78, 80, 95, 0xFF985E45, 3);
      box(c, x + 20, 185, 80, 95, 0xFF985E45, 3);
      box(c, x + 90, 183, 7, 15, 0xFFFFD88D, 3);
    }
    for (final x in [220.0, 770.0]) {
      c.drawCircle(
        Offset(x, 125),
        43 + math.sin(time * 3) * 2,
        Paint()..color = const Color(0x22FFDE91),
      );
      box(c, x - 4, 112, 8, 45, 0xFF7F4936);
      c.drawCircle(
        Offset(x, 104),
        12,
        Paint()..color = const Color(0xFFFFDA8A),
      );
    }
    box(c, 330, 45, 340, 83, 0xFF9C6242, 5);
    box(c, 338, 53, 324, 67, 0xFFEED5AF, 3);
    text(
      c,
      'COUPLE COURT',
      const Rect.fromLTWH(355, 67, 290, 40),
      size: 30,
      color: 0xFF815035,
    );
    // Judge's chair, articulated judge and raised bench.
    box(c, 439, 142, 122, 146, 0xFF392D32, 12);
    box(c, 447, 150, 106, 130, 0xFF586879, 8);
    actor(c, 500, 220, 2, .84);
    box(c, 317, 278, 366, 30, 0xFFE1A463, 4);
    box(c, 335, 307, 330, 107, 0xFF774832);
    box(c, 351, 320, 298, 79, 0xFFA66A44, 3);
    box(c, 416, 330, 168, 58, 0xFF8D573A, 3);
    text(
      c,
      closed ? 'ADJOURNED' : 'THE JUDGE',
      const Rect.fromLTWH(430, 348, 140, 30),
      size: 18,
    );
    // Participants stand separately on their own animated rigs.
    actor(c, 191, 352, 0, 1.12);
    actor(c, 809, 352, 1, 1.12);
    podium(c, 61, 397, names[0], speaker == 0 && talking);
    podium(c, 675, 397, names[1], speaker == 1 && talking);
    // Brass gallery rails give the stage foreground depth.
    for (final x in [22.0, 978.0]) {
      box(c, x - 5, 420, 10, 150, 0xFF51342B);
      c.drawCircle(
        Offset(x, 420),
        13,
        Paint()..color = const Color(0xFFE6BB72),
      );
    }
    line(c, const Offset(22, 446), const Offset(80, 481), 0xFFE6BB72, 7);
    line(c, const Offset(978, 446), const Offset(920, 481), 0xFFE6BB72, 7);
  }

  void podium(Canvas c, double x, double y, String name, bool lit) {
    if (lit) box(c, x - 9, y - 7, 282, 111, 0x55FFD18B, 10);
    box(c, x, y, 264, 21, 0xFFE2A164, 4);
    box(c, x + 12, y + 21, 240, 80, 0xFF663E30, 3);
    box(c, x + 26, y + 31, 212, 57, 0xFF9A5D3C, 2);
    text(c, name, Rect.fromLTWH(x + 36, y + 47, 192, 30), size: 20);
  }

  void actor(Canvas c, double x, double y, int id, double scale) {
    final active = speaker == id && talking;
    final sway = math.sin(time * (active ? 11 : 2) + id) * (active ? 2.8 : 1.0);
    c.save();
    c.translate(x, y + sway);
    c.scale(scale);
    if (active) {
      c.drawOval(
        const Rect.fromLTWH(-54, -75, 108, 138),
        Paint()..color = const Color(0x24FFE4A5),
      );
    }
    final shirt = id == 2
        ? 0xFF34303D
        : id == 0
        ? 0xFFDD8C75
        : 0xFF668F92;
    final skin = id == 2 ? 0xFFE0AF88 : 0xFFE9B795;
    // Independent arm movement is driven by the current speech event.
    for (final side in [-1, 1]) {
      final gesture = active ? math.sin(time * 8 + side) * .32 : 0.0;
      c.save();
      c.translate(side * 30.0, -3);
      c.rotate(side * (.45 + gesture));
      box(c, -8, 0, 16, 49, shirt, 8);
      box(c, -7, 40, 14, 17, skin, 6);
      c.restore();
    }
    box(c, -31, -13, 62, 77, shirt, 14);
    if (id == 2) {
      box(c, -11, -12, 8, 38, 0xFFFFF3D7, 2);
      box(c, 3, -12, 8, 38, 0xFFFFF3D7, 2);
    }
    box(c, -9, -24, 18, 20, skin, 4);
    if (id == 0) {
      box(c, -34, -82, 68, 92, 0xFF593C35, 23);
    }
    c.drawOval(
      const Rect.fromLTWH(-29, -82, 58, 66),
      Paint()..color = Color(skin),
    );
    final hair = id == 2
        ? 0xFFB5ADA1
        : id == 0
        ? 0xFF593C35
        : 0xFF684235;
    final tuft = Path()
      ..moveTo(-32, -52)
      ..lineTo(-33, -78)
      ..quadraticBezierTo(0, -111, 30, -79)
      ..lineTo(31, -49)
      ..lineTo(18, -69)
      ..lineTo(7, -75)
      ..lineTo(-7, -63)
      ..lineTo(-20, -68)
      ..close();
    c.drawPath(tuft, Paint()..color = Color(hair));
    final blink = (time + id * .85) % 4.3 < .14;
    for (final eye in [-11.0, 11.0]) {
      if (blink) {
        line(c, Offset(eye - 3, -50), Offset(eye + 3, -50), 0xFF382D2B, 2);
      } else {
        c.drawOval(
          Rect.fromCenter(center: Offset(eye, -50), width: 8, height: 11),
          Paint()..color = const Color(0xFFFFF6E9),
        );
        c.drawCircle(
          Offset(eye + 1, -49),
          2.5,
          Paint()..color = const Color(0xFF382D2B),
        );
      }
    }
    final mouth = active ? 4 + math.sin(time * 23).abs() * 5 : 2.0;
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(0, -31),
        width: active ? 14 : 12,
        height: mouth,
      ),
      Paint()..color = const Color(0xFF79433A),
    );
    if (id == 2) {
      // Gavel arm strikes in rhythm during a judge's line.
      c.save();
      c.translate(42, 4);
      c.rotate(active ? -.6 + math.sin(time * 9) * .6 : -.45);
      box(c, -4, -43, 8, 49, 0xFF9F643A, 3);
      box(c, -17, -53, 34, 17, 0xFFD29A58, 3);
      c.restore();
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _CourtPainter old) =>
      old.time != time ||
      old.speaker != speaker ||
      old.talking != talking ||
      old.closed != closed ||
      old.names.toString() != names.toString();
}
