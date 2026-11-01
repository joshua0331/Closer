class CourtLine {
  const CourtLine(this.key, this.speaker, this.text);
  final String key, text;

  /// 0 claimant, 1 respondent, 2 judge.
  final int speaker;
}

CourtLine hearingLine(Map<String, dynamic> state) {
  final phase = state['phase'] as int;
  String value(String field, [int? index]) {
    final content = state[field];
    if (index != null) {
      return content is List && content.length > index
          ? content[index].toString()
          : '';
    }
    return content?.toString() ?? '';
  }

  final previous = <int, (int, String)>{
    1: (0, value('requestedRemedy')),
    2: (0, value('statements', 0)),
    3: (1, value('statements', 1)),
    4: (0, value('crossQuestions', 0)),
    5: (1, value('crossAnswers', 1)),
    6: (1, value('crossQuestions', 1)),
    7: (0, value('crossAnswers', 0)),
    8: (0, value('rebuttals', 0)),
    9: (1, value('rebuttals', 1)),
    10: (
      2,
      'My questions: ${value('judgeQuestions', 0)} ${value('judgeQuestions', 1)}',
    ),
    11: (0, value('judgeAnswers', 0)),
    12: (1, value('judgeAnswers', 1)),
    13: (2, (state['ruling'] as Map?)?['proposedRemedy']?.toString() ?? ''),
    14: (1, 'I would like to appeal the proposed ruling.'),
    15: (1, value('appealReason')),
    16: (0, value('appealResponse')),
    17: (2, (state['ruling'] as Map?)?['proposedRemedy']?.toString() ?? ''),
    18: (
      2,
      state['closedStatus'] == 'accepted'
          ? 'Both of you have accepted the proposal. Court is adjourned.'
          : 'The case is closed without a mutual agreement.',
    ),
  };
  final line = previous[phase];
  final text = line == null || line.$2.trim().isEmpty
      ? (phase == 0
            ? 'Welcome to Couple Court. Prepare your evidence, then both enter the hearing when you are ready.'
            : 'The court is listening. Submit your turn below.')
      : line.$2;
  return CourtLine(
    'hearing:$phase:${state['joined']}:${state['closedStatus']}',
    line?.$1 ?? 2,
    text,
  );
}
