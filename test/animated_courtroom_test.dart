import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:closer/models/cloud_couple_store.dart';
import 'package:closer/screens/animated_courtroom.dart';
import 'package:closer/services/court_performance.dart';

void main() {
  test('Hearing dialogue maps to the person who actually submitted it', () {
    final state = <String, dynamic>{
      'phase': 2,
      'statements': ['My opening', ''],
      'joined': ['a', 'b'],
    };
    expect(hearingLine(state).speaker, 0);
    expect(hearingLine(state).text, 'My opening');
    state['phase'] = 13;
    state['ruling'] = {'proposedRemedy': 'Take turns with cleanup'};
    expect(hearingLine(state).speaker, 2);
    expect(hearingLine(state).text, 'Take turns with cleanup');
  });
  testWidgets(
    'Live chat triggers an animated line and reduced motion shows the complete text',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = CloudCoupleStore(
        await SharedPreferences.getInstance(),
        null,
        roomUid: 'a',
      );
      addTearDown(store.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: AnimatedCourtroom(
                  store: store,
                  hearing: const {
                    'phase': 0,
                    'names': ['Alex', 'Sam'],
                    'people': ['a', 'b'],
                    'joined': [],
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      store.messages.add({
        'id': 'm1',
        'kind': 'text',
        'text': 'Your honor, let us share the chores!',
        'senderId': 'a',
      });
      store.notifyListeners();
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.text('Alex is speaking'), findsOneWidget);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await tester.runAsync(() async {
        await Directory('build/visual-checks').create(recursive: true);
        await File('build/visual-checks/animated-courtroom.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
      image.dispose();
      await tester.tap(find.byTooltip('Reduce motion'));
      await tester.pump();
      expect(find.text('Your honor, let us share the chores!'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
