import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:closer/screens/room_gate.dart';
import 'package:closer/screens/room_chat.dart';
import 'package:closer/models/cloud_couple_store.dart';

class RoomStore extends CloudCoupleStore {
  RoomStore(SharedPreferences preferences)
    : super(
        preferences,
        null,
        roomUid: 'room_test',
        roomSession: 'room_private_test',
      );
  final sent = <String>[];
  @override
  Future<String> addMessage(
    String text, {
    bool summons = false,
    String? photoPath,
    Map<String, dynamic>? replyTo,
  }) async {
    sent.add(text);
    messages.add({'id': 'm1', 'kind': 'text', 'senderId': uid, 'text': text});
    notifyListeners();
    return 'm1';
  }
}

void main() {
  testWidgets(
    'Guest lobby requires a name and selfie without email or password',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: RoomGate(preferences: await SharedPreferences.getInstance()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your name'), findsOneWidget);
      expect(find.text('Upload my selfie'), findsOneWidget);
      expect(find.text('Email'), findsNothing);
      expect(find.text('Password'), findsNothing);
      await tester.ensureVisible(find.text('Create my courtroom'));
      await tester.tap(find.text('Create my courtroom'));
      await tester.pump();
      expect(find.textContaining('Add your name, selfie'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Room chat submits messages through the shared room store', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = RoomStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    store.yourName = 'Alex';
    store.partnerName = 'Sam';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RoomChat(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ready to hear your side.');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(store.sent, ['Ready to hear your side.']);
    expect(find.text('Ready to hear your side.'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
  });
}
