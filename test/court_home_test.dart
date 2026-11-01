import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:closer/models/cloud_couple_store.dart';
import 'package:closer/screens/court_home.dart';

class TestUser implements User {
  @override
  String get uid => 'alex';
  @override
  String? get displayName => 'Alex';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Court dashboard shows shared summons and excludes ordinary chat',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = CloudCoupleStore(
        await SharedPreferences.getInstance(),
        TestUser(),
      );
      addTearDown(store.dispose);
      store.messages.addAll([
        {
          'id': 'case1',
          'kind': 'court',
          'text': 'Who left the dishes?',
          'status': 'open',
        },
        {'id': 'chat1', 'kind': 'text', 'text': 'Private ordinary chat'},
      ]);
      await tester.pumpWidget(MaterialApp(home: CourtHome(store: store)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Who left the dishes?'), 300);
      expect(find.text('Who left the dishes?'), findsOneWidget);
      expect(find.text('Private ordinary chat'), findsNothing);
      expect(find.text('Map'), findsNothing);
      expect(find.text('Memories'), findsNothing);
    },
  );
}
