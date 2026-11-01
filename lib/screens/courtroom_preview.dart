import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cloud_couple_store.dart';
import 'animated_courtroom.dart';

/// An explicit local animation preview: it never creates a case or calls AI.
class CourtroomPreview extends StatefulWidget {
  const CourtroomPreview({super.key, required this.preferences});
  final SharedPreferences preferences;
  @override
  State<CourtroomPreview> createState() => _CourtroomPreviewState();
}

class _CourtroomPreviewState extends State<CourtroomPreview> {
  late final CloudCoupleStore _store;
  int _count = 0;
  Map<String, dynamic> _hearing = {
    'phase': 0,
    'names': ['Alex', 'Sam'],
    'people': ['preview_a', 'preview_b'],
    'joined': [],
  };
  @override
  void initState() {
    super.initState();
    _store = CloudCoupleStore(widget.preferences, null, roomUid: 'preview_a');
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  void _speak(int role) {
    if (role == 2) {
      setState(
        () => _hearing = {
          ..._hearing,
          'phase': _hearing['phase'] == 13 ? 17 : 13,
          'ruling': {
            'proposedRemedy': 'My suggestion: share the cleanup, then take a moment to hear each other out. The choice is yours.',
          },
        },
      );
    } else {
      _store.messages.add({
        'id': 'preview_${_count++}',
        'kind': 'text',
        'senderId': role == 0 ? 'preview_a' : 'preview_b',
        'text': role == 0
            ? 'Your honor, I would like us to share the chores more evenly!'
            : 'I hear you. Could we alternate the dishes each evening?',
      });
      _store.notifyListeners();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Courtroom preview · no live case')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              AnimatedCourtroom(store: _store, hearing: _hearing),
              const SizedBox(height: 16),
              const Text(
                'Try the character animations and sound effects. These example lines are a local preview, not an AI ruling.',
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 3; i++)
                    FilledButton.tonal(
                      onPressed: () => _speak(i),
                      child: Text(
                        ['Alex speaks', 'Sam speaks', 'Judge speaks'][i],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
