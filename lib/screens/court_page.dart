import 'dart:async';

import 'package:flutter/material.dart';

class CourtPage extends StatefulWidget {
  const CourtPage({
    super.key,
    this.firstName,
    this.secondName,
    this.issue,
    this.onAgreement,
  });
  final String? firstName, secondName, issue;
  final ValueChanged<String>? onAgreement;

  @override
  State<CourtPage> createState() => _CourtPageState();
}

class _CourtPageState extends State<CourtPage> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _issue = TextEditingController();
  final _agreement = TextEditingController();
  int _stage = 0;
  int _seconds = 120;
  Timer? _timer;
  DateTime? _deadline;
  bool get _running => _timer?.isActive ?? false;

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [_first, _second, _issue, _agreement]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _first.text = widget.firstName ?? '';
    _second.text = widget.secondName ?? '';
    _issue.text = widget.issue ?? '';
    if (_first.text.isNotEmpty &&
        _second.text.isNotEmpty &&
        _issue.text.isNotEmpty) {
      _stage = 1;
    }
  }

  void _pause() {
    _timer?.cancel();
    _deadline = null;
  }

  void _toggleTimer() {
    setState(() {
      if (_running) {
        _pause();
      } else if (_seconds > 0) {
        _deadline = DateTime.now().add(Duration(seconds: _seconds));
        _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
          final remaining = _deadline!
              .difference(DateTime.now())
              .inMilliseconds;
          setState(() {
            _seconds = remaining > 0 ? (remaining / 1000).ceil() : 0;
            if (_seconds == 0) _pause();
          });
        });
      }
    });
  }

  void _advance() {
    _pause();
    if (_stage == 3) {
      widget.onAgreement?.call(_agreement.text.trim());
    }
    setState(() {
      _stage++;
      _seconds = 120;
    });
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      maxLines: lines,
      maxLength: lines > 1 ? 1000 : 50,
      textCapitalization: TextCapitalization.sentences,
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Please enter $label.' : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Couple Court'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.balance_rounded,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Less arguing. More understanding.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A little structure for the disagreements that matter.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (_stage == 0) ..._setup(),
                  if (_stage == 1 || _stage == 2) ..._hearing(),
                  if (_stage == 3) ..._resolution(),
                  if (_stage == 4) ...[
                    const Icon(
                      Icons.favorite_rounded,
                      size: 48,
                      color: Color(0xFF8B3657),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Case closed, together.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_first.text.trim()} & ${_second.text.trim()}',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            Text(_issue.text.trim()),
                            const Divider(height: 32),
                            const Text(
                              'OUR AGREEMENT',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(_agreement.text.trim()),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () {
                        if (widget.onAgreement != null) {
                          Navigator.pop(context);
                          return;
                        }
                        setState(() {
                          _stage = 0;
                          _seconds = 120;
                          _issue.clear();
                          _agreement.clear();
                        });
                      },
                      child: Text(
                        widget.onAgreement == null
                            ? 'Start another case'
                            : 'Back to our space',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Preview agreement. Both turns were completed on this device.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'One person speaks. One person listens. Both deserve respect.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _setup() => [
    Text('Open a new case', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    const Text('Choose a small disagreement and find a next step together.'),
    const SizedBox(height: 20),
    Form(
      key: _form,
      child: Column(
        children: [
          _field(_first, 'First partner’s name'),
          _field(_second, 'Second partner’s name'),
          _field(_issue, 'What is the disagreement?', lines: 3),
        ],
      ),
    ),
    FilledButton.icon(
      onPressed: () {
        if (_form.currentState!.validate()) _advance();
      },
      icon: const Icon(Icons.gavel_rounded),
      label: const Text('Begin the hearing'),
    ),
  ];

  List<Widget> _hearing() => [
    Text(
      'HEARING · TURN $_stage OF 2',
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).colorScheme.primary),
    ),
    const SizedBox(height: 12),
    Text(
      '${_stage == 1 ? _first.text.trim() : _second.text.trim()}, you have the floor.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 16),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(_issue.text.trim()),
      ),
    ),
    const SizedBox(height: 16),
    const Text(
      'Explain what happened, how you felt, and what you need. Your partner listens without interrupting.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    Text(
      '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.displayLarge,
    ),
    const SizedBox(height: 8),
    Text(
      _seconds == 0
          ? 'Time is up. Finish your thought, then switch.'
          : 'Two minutes to be heard.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 20),
    FilledButton.icon(
      onPressed: _seconds == 0 ? null : _toggleTimer,
      icon: Icon(_running ? Icons.pause : Icons.play_arrow),
      label: Text(_running ? 'Pause timer' : 'Start timer'),
    ),
    TextButton(
      onPressed: () {
        setState(() {
          _pause();
          _seconds = 120;
        });
      },
      child: const Text('Reset timer'),
    ),
    const SizedBox(height: 8),
    OutlinedButton(
      onPressed: _advance,
      child: Text(_stage == 1 ? 'Next partner’s turn' : 'Find common ground'),
    ),
  ];

  List<Widget> _resolution() => [
    Text(
      'Find common ground',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 12),
    const Text(
      'Each share one thing you understand about the other person’s point of view. Then agree on one small action you can both take.',
    ),
    const SizedBox(height: 24),
    Form(
      key: _form,
      child: _field(_agreement, 'What will you both do next?', lines: 4),
    ),
    FilledButton(
      onPressed: () {
        if (_form.currentState!.validate()) _advance();
      },
      child: const Text('Close the case together'),
    ),
  ];
}
