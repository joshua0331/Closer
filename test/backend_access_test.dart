import 'dart:convert';

import 'package:closer/screens/demo_access_page.dart';
import 'package:closer/services/backend_access.dart';
import 'package:closer/services/judge_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'Demo access exchanges only a private code and expires on disconnect',
    () async {
      final access = BackendAccess(
        baseUrl: 'https://backend.example',
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://backend.example/auth/session',
          );
          expect(jsonDecode(request.body), {'code': 'private-judge-code'});
          expect(request.headers.containsKey('Authorization'), false);
          return http.Response(
            jsonEncode({
              'session_token': 's' * 40,
              'expires_at':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch /
                  1000,
            }),
            200,
          );
        }),
      );
      await access.connect('private-judge-code');
      expect(access.connected, true);
      expect(access.token, 's' * 40);
      access.disconnect();
      expect(access.connected, false);
      expect(access.token, '');
      access.dispose();
    },
  );

  test(
    'Demo credentials are never sent over an external HTTP address',
    () async {
      var calls = 0;
      final access = BackendAccess(
        baseUrl: 'http://external.example',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        access.connect('judge-code'),
        throwsA(isA<DemoAccessException>()),
      );
      expect(calls, 0);
      access.dispose();
    },
  );

  test(
    'Invalid codes and usage errors are reported without a model call',
    () async {
      final access = BackendAccess(
        baseUrl: 'https://backend.example',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'The demo code is invalid or unavailable.'}),
            401,
          ),
        ),
      );
      await expectLater(
        access.connect('wrong-code'),
        throwsA(isA<DemoAccessException>()),
      );
      expect(access.connected, false);
      access.dispose();
      final requestIds = <String>{};
      final judge = JudgeService(
        endpoint: 'https://backend.example/judge',
        token: 'session-token',
        client: MockClient((request) async {
          expect(requestIds.add(request.headers['X-Request-ID']!), true);
          return http.Response('{}', 429);
        }),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          judge.hear(topic: 'x', names: ['a', 'b'], statements: ['a', 'b']),
          throwsA(isA<JudgeException>()),
        );
      }
      expect(requestIds.length, 2);
      judge.close();
    },
  );

  testWidgets('Judges enter an app demo code without supplying an API key', (
    tester,
  ) async {
    final access = BackendAccess(
      baseUrl: 'https://backend.example',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'session_token': 't' * 40,
            'expires_at':
                DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch /
                1000,
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: DemoAccessPage(access: access)));
    await tester.enterText(find.byType(TextField), 'private-demo-code');
    await tester.ensureVisible(find.text('Connect to the demo'));
    await tester.tap(find.text('Connect to the demo'));
    await tester.pumpAndSettle();
    expect(find.text('Your AI demo is connected.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Disconnect demo'));
    await tester.pumpAndSettle();
    expect(access.connected, false);
    await tester.pumpWidget(const SizedBox());
    access.dispose();
  });
}
