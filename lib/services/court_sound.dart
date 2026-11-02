enum CourtSound {
  objection('objection.wav'),
  sustained('sustained.wav'),
  overruled('overruled.wav'),
  verdict('verdict.wav'),
  appealDecision('appeal_decision.wav'),
  accepted('accepted.wav'),
  unresolved('unresolved.wav'),
  evidence('evidence.wav'),
  turn('turn.wav'),
  courtroom('courtroom.wav'),
  judgeVoice('judge_voice.wav'),
  partnerVoice('partner_voice.wav'),
  typeTick('type_tick.wav');

  const CourtSound(this.fileName);

  final String fileName;
  String get asset => 'court_sounds/$fileName';
}
