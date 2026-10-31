import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:closer/models/cloud_couple_store.dart';
import 'package:closer/screens/shared_court.dart';

class _User implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  String? get displayName => uid == 'a' ? 'Alex' : 'Sam';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store extends CloudCoupleStore {
  _Store(super.preferences, super.user, this.state);
  Map<String, dynamic> state;
  final submissions = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> hearing(
    String id, {
    Map<String, dynamic>? body,
  }) async {
    if (body != null) {
      submissions.add(body);
      if (body['operation'] == 'turn') {
        state['phase'] = 2;
        state['version'] = 2;
      }
    }
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(state)) as Map);
  }

  @override
  Future<void> refresh() async {}
}

Map<String, dynamic> _case() => {
  'people': ['a', 'b'],
  'names': ['Alex', 'Sam'],
  'topic': 'Dishes',
  'phase': 1,
  'version': 1,
  'joined': ['a', 'b'],
  'deadline': DateTime.now().millisecondsSinceEpoch / 1000 + 120,
  'requestedRemedy': 'Share cleanup',
  'statements': ['', ''],
  'crossQuestions': ['', ''],
  'crossAnswers': ['', ''],
  'rebuttals': ['', ''],
  'judgeQuestions': ['', ''],
  'judgeAnswers': ['', ''],
  'evidence': [],
  'ruling': null,
  'approved': [],
};
void main() {
  testWidgets('Shared hearing locks the other role out of a speaking turn', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = _Store(
      await SharedPreferences.getInstance(),
      _User('b'),
      _case(),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SharedCourt(store: store, caseId: 'case1'),
      ),
    );
    await tester.pump();
    expect(
      find.text('Waiting for Alex to speak on their phone.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Your turn'), findsNothing);
    expect(store.submissions, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('A submitted turn uses server version and switches to waiting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = _Store(
      await SharedPreferences.getInstance(),
      _User('a'),
      _case(),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SharedCourt(store: store, caseId: 'case1'),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Your turn'),
      'I did the dishes.',
    );
    await tester.ensureVisible(find.text('Submit my turn'));
    await tester.tap(find.text('Submit my turn'));
    await tester.pump();
    expect(store.submissions.single['version'], 1);
    expect(store.submissions.single['text'], 'I did the dishes.');
    expect(
      find.text('Waiting for Sam to speak on their phone.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
