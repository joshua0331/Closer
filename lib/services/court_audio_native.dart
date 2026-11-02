import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'court_sound.dart';

class CourtAudio {
  final AudioPlayer _effects = AudioPlayer();
  final AudioPlayer _voice = AudioPlayer();
  final AudioPlayer _typing = AudioPlayer();

  bool enabled = true;

  bool toggle() => enabled = !enabled;

  void play(CourtSound sound) => _play(sound, _effects, volume: 0.34);

  void cue(bool judge) => _play(
    judge ? CourtSound.judgeVoice : CourtSound.partnerVoice,
    _voice,
    volume: 0.20,
  );

  void blip(int tick) {
    if (tick % 4 == 0) {
      _play(CourtSound.typeTick, _typing, volume: 0.10);
    }
  }

  void _play(CourtSound sound, AudioPlayer player, {required double volume}) {
    if (!enabled) return;
    unawaited(() async {
      try {
        await player.stop();
        await player.play(AssetSource(sound.asset), volume: volume);
      } catch (_) {
        // Sound is optional and must never interrupt the hearing.
      }
    }());
  }

  void dispose() {
    unawaited(_effects.dispose());
    unawaited(_voice.dispose());
    unawaited(_typing.dispose());
  }
}
