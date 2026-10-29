import 'dart:convert';
import 'dart:typed_data';

import 'package:closer/services/muse_image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final png = Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ...List.filled(20, 0),
  ]);
  test('Muse client sends both references to the image route and preserves provenance', () async {
    final service = MuseImageService(
      endpoint: 'https://court.example/characters',
      token: 'demo',
      client: MockClient((request) async {
        expect(request.url.path, '/characters');
        expect(jsonDecode(request.body), {
          'photos': [base64Encode(png), base64Encode(png)],
        });
        return http.Response(
          jsonEncode({
            'image_base64': base64Encode(png),
            'model': 'muse-image-1.0',
            'response_id': 'resp-test',
            'prompt_version': 'couple-court-scene-v1',
          }),
          200,
        );
      }),
    );
    final scene = await service.generate([png, png]);
    expect(scene.model, 'muse-image-1.0');
    expect(scene.responseId, 'resp-test');
    expect(scene.bytes, png);
    service.close();
  });

  test('Unconfigured or invalid artwork requests fail explicitly', () async {
    final missing = MuseImageService(endpoint: '', token: '');
    await expectLater(
      missing.generate([png, png]),
      throwsA(isA<ArtworkException>()),
    );
    missing.close();
    final service = MuseImageService(
      endpoint: 'https://court.example/characters',
      token: 'demo',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      service.generate([png]),
      throwsA(isA<ArtworkException>()),
    );
    await expectLater(
      service.generate([png, png]),
      throwsA(isA<ArtworkException>()),
    );
    service.close();
  });
}
