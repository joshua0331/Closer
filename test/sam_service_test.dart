import 'dart:convert';

import 'package:closer/services/judge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'SAM client sends authenticated original and accepts empty matches',
    () async {
      final service = JudgeService(
        endpoint: 'https://court.example/judge',
        token: 'test-session',
        client: MockClient((request) async {
          expect(request.url.path, '/segment');
          expect(request.headers['Authorization'], 'Bearer test-session');
          expect(request.headers['X-Request-ID'], isNotEmpty);
          expect(jsonDecode(request.body), {
            'image_base64': 'original-photo',
            'prompt': 'plate',
          });
          return http.Response(
            jsonEncode({'model': 'sam-3.1', 'boxes': []}),
            200,
          );
        }),
      );
      addTearDown(service.close);
      expect(await service.segment('original-photo', 'plate'), isEmpty);
    },
  );
  test('SAM client rejects out of bounds or wrong-model highlights', () async {
    for (final model in ['sam-3.1', 'invented']) {
      final service = JudgeService(
        endpoint: 'https://court.example/judge',
        token: 'test-session',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'model': model,
              'boxes': [
                {'left': -1, 'top': 0, 'right': 1, 'bottom': 1},
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(service.close);
      await expectLater(
        service.segment('original', 'plate'),
        throwsA(isA<JudgeException>()),
      );
    }
  });
}
