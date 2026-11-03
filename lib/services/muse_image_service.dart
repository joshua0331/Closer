import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backend_access.dart';

class GeneratedScene {
  const GeneratedScene(
    this.bytes,
    this.model,
    this.responseId,
    this.promptVersion,
  );
  final Uint8List bytes;
  final String model, responseId, promptVersion;
}

class MuseImageService {
  MuseImageService({http.Client? client, String? endpoint, String? token})
    : _client = client ?? http.Client(),
      endpoint = endpoint ?? _endpoint(),
      _explicitToken = token;
  final http.Client _client;
  final String endpoint;
  final String? _explicitToken;
  String get token => _explicitToken ?? defaultApiToken(endpoint);
  bool get configured =>
      endpoint.isNotEmpty &&
      (token.isNotEmpty || hasAccountAccessFor(endpoint));
  static String _endpoint() {
    if (BackendAccess.instance.available) {
      try {
        return BackendAccess.instance.url('characters');
      } catch (_) {
        return '';
      }
    }
    const direct = String.fromEnvironment('CHARACTER_URL');
    if (direct.isNotEmpty) return direct;
    const judge = String.fromEnvironment('JUDGE_URL');
    if (judge.isEmpty) return '';
    return Uri.parse(judge).resolve('characters').toString();
  }

  void close() => _client.close();

  Future<GeneratedScene> generate(List<Uint8List> photos) async {
    if (!configured) {
      throw const ArtworkException(
        'Muse Image is not connected yet. Your selected photos have not been uploaded.',
      );
    }
    if (photos.length != 2 ||
        photos.any((bytes) => bytes.isEmpty || bytes.length > 1000000)) {
      throw const ArtworkException(
        'Choose two PNG or JPEG portraits smaller than 1 MB each.',
      );
    }
    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization':
                  'Bearer ${_explicitToken ?? await authenticatedApiToken(endpoint)}',
              'X-Request-ID': newRequestId(),
            },
            body: jsonEncode({'photos': photos.map(base64Encode).toList()}),
          )
          .timeout(const Duration(seconds: 200));
      final accessError = demoErrorMessage(response.statusCode);
      if (accessError != null) throw ArtworkException(accessError);
      if (response.statusCode != 200) {
        throw const ArtworkException(
          'Muse Image could not finish your scene. Please try again.',
        );
      }
      if (response.bodyBytes.length > 18000000) throw const FormatException();
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['model'] != 'muse-image-1.0' ||
          data['image_base64'] is! String ||
          data['response_id'] is! String ||
          data['prompt_version'] is! String) {
        throw const FormatException();
      }
      final bytes = base64Decode(data['image_base64'] as String);
      if (bytes.length < 24 ||
          bytes.length > 12000000 ||
          !List.generate(
            8,
            (index) => bytes[index],
          ).join(',').startsWith('137,80,78,71,13,10,26,10')) {
        throw const FormatException();
      }
      return GeneratedScene(
        bytes,
        data['model'] as String,
        data['response_id'] as String,
        data['prompt_version'] as String,
      );
    } on ArtworkException {
      rethrow;
    } on TimeoutException {
      throw const ArtworkException(
        'Generation is taking too long. No new scene was saved. You can retry.',
      );
    } catch (_) {
      throw const ArtworkException(
        'Could not load the generated artwork. Your current scene is unchanged.',
      );
    }
  }
}

class ArtworkException implements Exception {
  const ArtworkException(this.message);
  final String message;
}
