import 'dart:convert';

import 'package:couple_court/theme/us_theme.dart';
import 'package:couple_court/models/couple_store.dart';
import 'package:couple_court/screens/court_experience.dart';
import 'package:couple_court/services/judge_service.dart';
import 'package:couple_court/services/muse_image_service.dart';
import 'package:couple_court/screens/courtroom_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> tap(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'Meta judge client sends testimony and does not transmit photos',
    () async {
      final service = JudgeService(
        endpoint: 'https://court.example/judge',
        token: 'demo',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer demo');
          expect(jsonDecode(request.body), {
            'topic': 'Chores',
            'names': ['Alex', 'Sam'],
            'statements': ['Dishes', 'Laundry'],
          });
          return http.Response(
            jsonEncode({'verdict': 'Take turns.', 'model': 'muse-spark-1.3'}),
            200,
          );
        }),
      );
      final result = await service.hear(
        topic: 'Chores',
        names: ['Alex', 'Sam'],
        statements: ['Dishes', 'Laundry'],
      );
      expect(result.model, 'muse-spark-1.3');
      expect(result.text, 'Take turns.');
      service.close();
    },
  );

  test(
    'Missing setup and invalid upstream replies are explicit errors',
    () async {
      final missing = JudgeService(endpoint: '', token: '');
      await expectLater(
        missing.hear(topic: 'x', names: ['a', 'b'], statements: ['a', 'b']),
        throwsA(isA<JudgeException>()),
      );
      missing.close();
      for (final response in [
        http.Response('error', 502),
        http.Response('{}', 200),
      ]) {
        final service = JudgeService(
          endpoint: 'https://court.example/judge',
          token: 'demo',
          client: MockClient((_) async => response),
        );
        await expectLater(
          service.hear(topic: 'x', names: ['a', 'b'], statements: ['a', 'b']),
          throwsA(isA<JudgeException>()),
        );
        service.close();
      }
    },
  );

  testWidgets(
    'Complete hearing includes cross-examination, judge questions, compensation and appeal',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final actions = <String>[];
      final service = JudgeService(
        endpoint: 'https://court.example/judge',
        token: 'demo',
        client: MockClient((request) async {
          expect(request.url.path, '/hearing');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final action = payload['action'] as String;
          final docket = payload['case'] as Map<String, dynamic>;
          actions.add(action);
          expect(docket['requestedRemedy'], 'Cook dinner once');
          expect(docket['statements'], ['I washed dishes.', 'I did laundry.']);
          expect(docket['crossAnswers'], ['Yesterday.', 'On Tuesday.']);
          expect(docket['rebuttals'], [
            'Here is my clarification.',
            'Here is my response.',
          ]);
          if (action == 'questions') {
            return http.Response(
              jsonEncode({
                'model': 'muse-spark-1.3',
                'result': {
                  'questions': [
                    'What is missing from the chore split?',
                    'What can you willingly do?',
                  ],
                  'evidenceReview': [],
                },
              }),
              200,
            );
          }
          expect(docket['judgeAnswers'], ['An agreed schedule.', 'Cook once.']);
          if (action == 'appeal') {
            expect(docket['appealReason'], 'Twice is disproportionate.');
            expect(docket['appealResponse'], 'Once is acceptable.');
            expect(
              docket['priorRuling']['proposedRemedy'],
              'Cook dinner twice',
            );
          }
          return http.Response(
            jsonEncode({
              'model': 'muse-spark-1.3',
              'result': {
                'decision': action == 'appeal' ? 'reduce' : 'increase',
                'requestedRemedy': 'Cook dinner once',
                'proposedRemedy': action == 'appeal'
                    ? 'Cook dinner once'
                    : 'Cook dinner twice',
                'reasoning': 'Consider both accounts.',
                'uncertainties': 'The accounts are unverified.',
                'evidenceReview': [],
              },
            }),
            200,
          );
        }),
      );
      Future<void> fill(String label, String value) async {
        final field = find.byKey(ValueKey(label));
        if (field.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            field,
            220,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pump();
      }

      await tester.pumpWidget(
        MaterialApp(
          home: CourtExperience(preferences: prefs, judge: service),
        ),
      );
      await fill('Claimant’s name (filing the case)', 'Alex');
      await fill('Respondent’s name', 'Sam');
      await fill('What is the disagreement?', 'Sharing chores');
      await fill(
        'What compensation or action are you requesting?',
        'Cook dinner once',
      );
      await tap(tester, 'Enter the courtroom');
      await fill('Your opening statement', 'I washed dishes.');
      await tap(tester, 'Hear the respondent');
      await fill('Your opening statement', 'I did laundry.');
      await tap(tester, 'Begin cross-examination');
      await fill('Question for your partner', 'When did you do laundry?');
      await tap(tester, 'Give your partner the floor');
      await fill('Your answer', 'On Tuesday.');
      await tap(tester, 'Ask the claimant a question');
      await fill('Question for your partner', 'When did you wash dishes?');
      await tap(tester, 'Give your partner the floor');
      await fill('Your answer', 'Yesterday.');
      await tap(tester, 'Begin rebuttals');
      await fill('Your rebuttal', 'Here is my clarification.');
      await tap(tester, 'Hear the respondent’s rebuttal');
      await fill('Your rebuttal', 'Here is my response.');
      await tap(tester, 'Review the case');
      await tap(tester, 'Ask judge to examine evidence');
      expect(actions, isEmpty);
      await tap(tester, 'Send to the judge');
      await fill('Answer the judge', 'An agreed schedule.');
      await tap(tester, 'Judge’s question for the respondent');
      await fill('Answer the judge', 'Cook once.');
      await tap(tester, 'Prepare the final verdict');
      await tap(tester, 'Request final verdict');
      await tap(tester, 'Send to the judge');
      expect(find.text('Cook dinner twice'), findsOneWidget);
      await tap(tester, 'Respondent: appeal this ruling');
      await fill('Grounds for appeal', 'Twice is disproportionate.');
      await tap(tester, 'Let the claimant respond');
      await fill('Response to the appeal', 'Once is acceptable.');
      await tap(tester, 'Review the appeal');
      await tap(tester, 'Submit appeal to judge');
      await tap(tester, 'Send to the judge');
      expect(actions, ['questions', 'verdict', 'appeal']);
      expect(find.text('The appeal decision'), findsOneWidget);
      await tap(tester, 'Alex accepts this proposal');
      await tap(tester, 'Sam accepts this proposal');
      await tap(tester, 'Accept & close case');
      final saved = jsonDecode(prefs.getString('court_cases_v1')!).single;
      expect(saved['agreement'], 'Cook dinner once');
      expect(saved['rulingHistory'].length, 2);
      expect(saved['case']['crossQuestions'][0], 'When did you do laundry?');
      expect(saved['status'], 'accepted');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.close();
    },
  );

  testWidgets('Expired testimony locks input and never invents a statement', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'court_profile_v1': jsonEncode({
        'names': ['Alex', 'Sam'],
        'photos': [null, null],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime(2026, 10, 29, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: CourtExperience(preferences: prefs, now: () => now),
      ),
    );
    Future<void> fill(String label, String value) async {
      final field = find.byKey(ValueKey(label));
      await tester.scrollUntilVisible(
        field,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(field, value);
    }

    await fill('What is the disagreement?', 'Chores');
    await fill(
      'What compensation or action are you requesting?',
      'Cook dinner once',
    );
    await tap(tester, 'Enter the courtroom');
    now = now.add(const Duration(seconds: 121));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('Your opening statement')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      true,
    );
    await tap(tester, 'Time is up — continue');
    expect(find.text('Sam, the floor is yours.'), findsOneWidget);
    expect(
      find.text('[No response supplied before the time limit.]'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Portrait selection is never overlaid and cancelling Muse consent sends nothing',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'court_profile_v1': jsonEncode({
          'names': ['Alex', 'Sam'],
          'photos': ['left-photo.jpg', 'right-photo.jpg'],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      var calls = 0;
      final imageService = MuseImageService(
        endpoint: 'https://court.example/characters',
        token: 'demo',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CourtExperience(preferences: prefs, artwork: imageService),
        ),
      );
      expect(
        tester
            .widget<CourtroomScene>(find.byType(CourtroomScene))
            .generatedScene,
        isNull,
      );
      expect(find.byType(ClipOval), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Create our characters with Muse Image'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, 'Create our characters with Muse Image');
      expect(find.textContaining('Both selected portraits'), findsOneWidget);
      expect(calls, 0);
      await tap(tester, 'Cancel');
      expect(calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      imageService.close();
    },
  );

  testWidgets('Courtroom layout fits portrait and landscape', (tester) async {
    await tester.runAsync(() async {
      await (FontLoader('CoupleSans')
            ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    SharedPreferences.setMockInitialValues({});
    final store = CoupleStore(await SharedPreferences.getInstance());
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(400, 900), const Size(1000, 650)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildCloserTheme(),
          home: CourtExperience(preferences: store.preferences),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      expect(find.text('COUPLE COURT'), findsOneWidget);
      expect(find.text('Map'), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CourtExperience),
        matchesGoldenFile('goldens/court-${size.width.toInt()}.png'),
      );
    }
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
