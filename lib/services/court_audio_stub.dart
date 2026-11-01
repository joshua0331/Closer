class CourtAudio {
  bool enabled = false;
  bool toggle() => enabled = !enabled;
  void cue(bool judge) {}
  void blip(int tick) {}
  void dispose() {}
}
