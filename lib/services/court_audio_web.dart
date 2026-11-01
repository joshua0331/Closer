import 'dart:js_interop';

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
  bool enabled = false;
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
      /* Audio never interrupts a hearing. */
    }
  }

  void cue(bool judge) {
    if (judge) {
      _tone(160, .14, 0, gain: .11, knock: true);
      _tone(120, .12, .18, gain: .08, knock: true);
    } else {
      _tone(520, .10, 0);
      _tone(700, .12, .09);
    }
  }

  void blip(int tick) => _tone(380 + (tick % 4) * 35, .025, 0, gain: .012);
  void dispose() {
    enabled = false;
    _context?.close().toDart.catchError((_) => null);
    _context = null;
  }
}
