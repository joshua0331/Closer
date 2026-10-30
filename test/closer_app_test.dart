import 'dart:convert';

import 'package:closer/main.dart';
import 'package:closer/models/couple_store.dart';
import 'package:closer/screens/court_experience.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> press(WidgetTester tester, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await rootBundle.loadString('assets/maps/countries.geojson');
  });
  test('Closer retains old profiles, photos, replies and reactions', () async {
    SharedPreferences.setMockInitialValues({
      'court_profile_v1': jsonEncode({
        'names': ['Alex', 'Sam'],
        'photos': [null, null],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = CoupleStore(prefs);
    expect(store.yourName, 'Alex');
    expect(store.partnerName, 'Sam');
    final original = await store.addMessage('Thinking of you');
    await store.toggleHeart(original);
    await store.addMessage(
      '',
      photoPath: '/local/photo.jpg',
      replyTo: store.messages.first,
    );
    final restored = CoupleStore(prefs);
    expect(restored.messages.first['hearted'], true);
    expect(restored.messages.last['kind'], 'photo');
    expect((restored.messages.last['replyTo'] as Map)['id'], original);
    store.dispose();
    restored.dispose();
  });

  testWidgets('Closer combines five tabs and chat reply and heart actions', (
    tester,
  ) async {
    phone(tester);
    SharedPreferences.setMockInitialValues({});
    final store = CoupleStore(await SharedPreferences.getInstance());
    store.yourName = 'Alex';
    store.partnerName = 'Sam';
    await store.save();
    await tester.pumpWidget(CloserApp(store: store));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Closer',
    );
    for (final label in ['Map', 'Court', 'Memories', 'Chat', 'Closer']) {
      expect(find.text(label), findsWidgets);
    }
    await press(tester, 'Chat');
    await tester.enterText(find.byType(TextField), 'Thinking of you');
    await tester.tap(find.byTooltip('Save local message'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Message options'));
    await tester.pumpAndSettle();
    await press(tester, 'Add a heart');
    expect(store.messages.first['hearted'], true);
    await tester.tap(find.byTooltip('Message options'));
    await tester.pumpAndSettle();
    await press(tester, 'Reply');
    await tester.enterText(find.byType(TextField), 'See you soon');
    await tester.tap(find.byTooltip('Save local message'));
    await tester.pumpAndSettle();
    expect((store.messages.last['replyTo'] as Map)['text'], 'Thinking of you');
    expect(find.byTooltip('Attach chat photo'), findsOneWidget);
    await press(tester, 'Memories');
    expect(find.text('Add a memory'), findsOneWidget);
    await press(tester, 'Closer');
    expect(find.text('Our anniversary'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'Chat summons opens advanced court and restores an unfinished draft',
    (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = CoupleStore(prefs);
      store.yourName = 'Alex';
      store.partnerName = 'Sam';
      await store.save();
      await tester.pumpWidget(CloserApp(store: store));
      await press(tester, 'Chat');
      await tester.tap(find.byTooltip('Summon partner'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Sharing chores');
      await press(tester, 'Add court summons');
      await press(tester, 'Enter Couple Court');
      expect(find.byType(CourtExperience), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('Claimant’s name (filing the case)')),
            )
            .controller!
            .text,
        'Alex',
      );
      final remedy = find.byKey(
        const ValueKey('What compensation or action are you requesting?'),
      );
      await tester.scrollUntilVisible(
        remedy,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(remedy, 'Cook dinner once');
      await press(tester, 'Enter the courtroom');
      await tester.enterText(
        find.byKey(const ValueKey('Your opening statement')),
        'I washed the dishes.',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pageBack();
      await tester.pumpAndSettle();
      final id = store.messages.single['id'] as String;
      expect(prefs.getString('court_draft_$id'), isNotNull);
      await press(tester, 'Enter Couple Court');
      expect(find.text('Alex, the floor is yours.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('Your opening statement')),
            )
            .controller!
            .text,
        'I washed the dishes.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      store.dispose();
    },
  );

  testWidgets('Accepted practice case updates its originating chat card', (
    tester,
  ) async {
    phone(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = CoupleStore(prefs);
    store.yourName = 'Alex';
    store.partnerName = 'Sam';
    final id = await store.addMessage('Chores', summons: true);
    final fields = <String, String>{
      'name0': 'Alex',
      'name1': 'Sam',
      'topic': 'Chores',
      'request': 'Cook dinner once',
      'agreement': '',
      'appealReason': '',
      'appealResponse': '',
      for (var i = 0; i < 2; i++) ...{
        'statement$i': 'Opening $i',
        'crossQuestion$i': 'Question $i',
        'crossAnswer$i': 'Answer $i',
        'rebuttal$i': 'Rebuttal $i',
        'judgeAnswer$i': '',
      },
    };
    await prefs.setString(
      'court_draft_$id',
      jsonEncode({
        'fields': fields,
        'stage': 9,
        'turnSeconds': 120,
        'remaining': 120,
        'deadline': null,
        'photos': [null, null],
        'generatedScene': null,
        'artResponseId': null,
        'promptVersion': null,
        'evidence': [],
        'exhibitCounter': 0,
        'evidenceReview': [],
        'judgeQuestions': ['', ''],
        'ruling': null,
        'rulingHistory': [],
        'model': null,
        'practice': false,
        'hasAppealed': false,
        'approved': [false, false],
      }),
    );
    await tester.pumpWidget(CloserApp(store: store));
    await press(tester, 'Chat');
    await press(tester, 'Enter Couple Court');
    await press(tester, 'Use practice questions');
    await tester.enterText(
      find.byKey(const ValueKey('Answer the judge')),
      'A shared schedule',
    );
    await press(tester, 'Judge’s question for the respondent');
    await tester.enterText(
      find.byKey(const ValueKey('Answer the judge')),
      'Cook once',
    );
    await press(tester, 'Prepare the final verdict');
    await press(tester, 'Try a practice verdict');
    await press(tester, 'Alex accepts this proposal');
    await press(tester, 'Sam accepts this proposal');
    await press(tester, 'Accept & close case');
    await press(tester, 'Back to Closer');
    expect(find.text('Court · case closed'), findsOneWidget);
    expect(store.messages.single['courtStatus'], 'accepted');
    expect(store.messages.single['recordId'], id);
    expect(prefs.getString('court_draft_$id'), isNull);
    expect(store.courtHistory.single['id'], id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('Closer map design remains the home screen', (tester) async {
    phone(tester);
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
    store.yourName = 'Alex';
    store.partnerName = 'Sam';
    await tester.runAsync(
      () => rootBundle.loadString('assets/maps/countries.geojson'),
    );
    await tester.pumpWidget(CloserApp(store: store));
    for (var frame = 0; frame < 20; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CloserApp),
      matchesGoldenFile('goldens/closer-home.png'),
    );
    expect(find.textContaining('Locations not connected'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}

