import 'dart:async';
import 'dart:js_interop';

import 'court_sound.dart';

@JS('AudioContext')
extension type _Context._(JSObject _) implements JSObject {
  external factory _Context();
  external double get currentTime;
  external String get state;
  external _Node get destination;
  external _Node createOscillator();
  external _Node createGain();
  external JSPromise<JSAny?> resume();
  external JSPromise<JSAny?> suspend();
  external JSPromise<JSAny?> close();
}

extension type _Node._(JSObject _) implements JSObject {
  external _Param get frequency;
  external _Param get gain;
  external set type(String value);
  external void connect(_Node node);
  external void start(double time);
  external void stop(double time);
}

extension type _Param._(JSObject _) implements JSObject {
  external void setValueAtTime(double value, double time);
  external void exponentialRampToValueAtTime(double value, double time);
}

class CourtAudio {
  _Context? _context;
  bool enabled = true;

  bool toggle() {
    try {
      _context ??= _Context();
      enabled = !enabled;
      if (enabled) {
        _context!.resume().toDart.catchError((_) => null);
      } else {
        _context!.suspend().toDart.catchError((_) => null);
      }
    } catch (_) {
      enabled = false;
    }
    return enabled;
  }

  void _tone(
    double hz,
    double length,
    double delay, {
    double gain = .035,
    bool knock = false,
  }) {
    final context = _context;
    if (!enabled || context == null || context.state != 'running') return;
    try {
      final oscillator = context.createOscillator(),
          volume = context.createGain();
      final at = context.currentTime + delay;
      oscillator.type = knock ? 'triangle' : 'sine';
      oscillator.frequency.setValueAtTime(hz, at);
      if (knock) {
        oscillator.frequency.exponentialRampToValueAtTime(38, at + length);
      }
      volume.gain.setValueAtTime(.0001, at);
      volume.gain.exponentialRampToValueAtTime(gain, at + .005);
      volume.gain.exponentialRampToValueAtTime(.0001, at + length);
      oscillator.connect(volume);
      volume.connect(context.destination);
      oscillator.start(at);
      oscillator.stop(at + length + .01);
    } catch (_) {
      // Audio is optional and must never interrupt a hearing.
    }
  }

  void play(CourtSound sound) {
    if (!enabled) return;
    try {
      _context ??= _Context();
    } catch (_) {
      return;
    }
    unawaited(_resumeAndPlay(sound));
  }

  Future<void> _resumeAndPlay(CourtSound sound) async {
    final context = _context;
    if (context == null) return;
    try {
      if (context.state != 'running') await context.resume().toDart;
    } catch (_) {
      return;
    }
    if (enabled) _playTones(sound);
  }

  void _playTones(CourtSound sound) {
    switch (sound) {
      case CourtSound.objection:
        _tone(145, .16, 0, gain: .12, knock: true);
        _tone(130, .13, .22, gain: .10, knock: true);
        return;
      case CourtSound.sustained:
        _tone(150, .14, 0, gain: .09, knock: true);
        _tone(659, .18, .14, gain: .035);
        _tone(784, .22, .30, gain: .03);
        return;
      case CourtSound.overruled:
        _tone(150, .15, 0, gain: .12, knock: true);
        _tone(440, .18, .17, gain: .03);
        _tone(330, .20, .34, gain: .028);
        return;
      case CourtSound.verdict:
        _tone(150, .14, 0, gain: .10, knock: true);
        _tone(523, .30, .10, gain: .035);
        _tone(659, .32, .30, gain: .035);
        _tone(784, .42, .53, gain: .03);
        return;
      case CourtSound.appealDecision:
        _tone(145, .14, 0, gain: .09, knock: true);
        _tone(392, .28, .12, gain: .03);
        _tone(523, .30, .32, gain: .032);
        _tone(698, .40, .55, gain: .03);
        return;
      case CourtSound.accepted:
        _tone(523, .22, 0, gain: .03);
        _tone(659, .26, .18, gain: .03);
        _tone(784, .36, .39, gain: .028);
        return;
      case CourtSound.unresolved:
        _tone(440, .28, 0, gain: .025);
        _tone(349, .34, .26, gain: .022);
        return;
      case CourtSound.evidence:
        _tone(1260, .035, 0, gain: .02);
        _tone(940, .04, .11, gain: .018);
        _tone(587, .16, .20, gain: .02);
        return;
      case CourtSound.turn:
        _tone(587, .14, 0, gain: .022);
        _tone(740, .16, .14, gain: .02);
        return;
      case CourtSound.courtroom:
        _tone(145, .14, 0, gain: .10, knock: true);
        _tone(130, .13, .22, gain: .08, knock: true);
        _tone(659, .26, .42, gain: .025);
        return;
      case CourtSound.judgeVoice:
        _tone(196, .10, 0, gain: .016);
        _tone(220, .10, .11, gain: .014);
        return;
      case CourtSound.partnerVoice:
        _tone(523, .09, 0, gain: .014);
        _tone(659, .10, .10, gain: .012);
        return;
      case CourtSound.typeTick:
        _tone(740, .018, 0, gain: .009);
        return;
    }
  }

  void cue(bool judge) =>
      play(judge ? CourtSound.judgeVoice : CourtSound.partnerVoice);

  void blip(int tick) {
    if (tick % 4 == 0) play(CourtSound.typeTick);
  }

  void dispose() {
    enabled = false;
    _context?.close().toDart.catchError((_) => null);
    _context = null;
  }
}
