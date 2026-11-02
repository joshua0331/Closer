import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_access.dart';

class JudgeResult {
  const JudgeResult(this.text, this.model);
  final String text, model;
}

class JudgeService {
  JudgeService({http.Client? client, String? endpoint, String? token})
    : _client = client ?? http.Client(),
      endpoint = endpoint ?? defaultJudgeUrl(),
      _explicitToken = token;
  final http.Client _client;
  final String endpoint;
  final String? _explicitToken;
  String get token => _explicitToken ?? defaultApiToken(endpoint);
  bool get configured => endpoint.isNotEmpty && token.isNotEmpty;
  void close() => _client.close();

  Future<List<Map<String, dynamic>>> segment(
    String image,
    String prompt,
  ) async {
    if (!configured) {
      throw const JudgeException('Connect AI demo access first.');
    }
    try {
      final response = await _client
          .post(
            Uri.parse(endpoint).resolve('segment'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'X-Request-ID': newRequestId(),
            },
            body: jsonEncode({'image_base64': image, 'prompt': prompt}),
          )
          .timeout(const Duration(seconds: 90));
      final error = demoErrorMessage(response.statusCode);
      if (error != null) throw JudgeException(error);
      if (response.statusCode != 200 || response.bodyBytes.length > 30000) {
        throw const FormatException();
      }
      final data = jsonDecode(response.body);
      if (data['model'] != 'sam-3.1' ||
          data['boxes'] is! List ||
          (data['boxes'] as List).length > 50) {
        throw const FormatException();
      }
      return (data['boxes'] as List).map((box) {
        for (final key in ['left', 'top', 'right', 'bottom']) {
          if (box[key] is! num ||
              !(box[key] as num).isFinite ||
              box[key] < 0 ||
              box[key] > 1) {
            throw const FormatException();
          }
        }
        if (box['left'] >= box['right'] || box['top'] >= box['bottom']) {
          throw const FormatException();
        }
        return Map<String, dynamic>.from(box as Map);
      }).toList();
    } on JudgeException {
      rethrow;
    } catch (_) {
      throw const JudgeException(
        'SAM could not complete this request. The original photo is unchanged.',
      );
    }
  }

  Future<HearingReply> hearing(
    String action,
    Map<String, dynamic> docket,
  ) async {
    if (!configured) {
      throw const JudgeException(
        'Metherapy Meta AI is not connected. Practice mode does not examine photos.',
      );
    }
    try {
      final uri = Uri.parse(endpoint).resolve('hearing');
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'X-Request-ID': newRequestId(),
            },
            body: jsonEncode({'action': action, 'case': docket}),
          )
          .timeout(const Duration(seconds: 90));
      final accessError = demoErrorMessage(response.statusCode);
      if (accessError != null) throw JudgeException(accessError);
      if (response.statusCode != 200 || response.bodyBytes.length > 300000) {
        throw const JudgeException(
          'Metherapy could not complete this step. Your session is unchanged; please retry.',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final model = data['model'];
      final result = data['result'];
      if (model is! String ||
          model.isEmpty ||
          result is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final reviews = result['evidenceReview'];
      if (reviews is! List) throw const FormatException();
      final ids = (docket['evidence'] as List).map((e) => e['id']).toSet();
      final seen = <String>{};
      for (final review in reviews) {
        if (review is! Map ||
            review['id'] is! String ||
            review['observation'] is! String ||
            review['limitation'] is! String ||
            !ids.contains(review['id']) ||
            !seen.add(review['id'] as String)) {
          throw const FormatException();
        }
      }
      if (seen.length != ids.length) throw const FormatException();
      if (action == 'questions') {
        final questions = result['questions'];
        if (questions is! List ||
            questions.length != 2 ||
            questions.any((q) => q is! String || q.trim().isEmpty)) {
          throw const FormatException();
        }
      } else {
        if (!{
              'aligned',
              'adapted',
              'alternative',
              'pause',
              // Legacy responses remain readable if the hosted backend is older.
              'grant',
              'reduce',
              'increase',
              'deny',
            }.contains(result['decision']) ||
            result['requestedRemedy'] != docket['requestedRemedy']) {
          throw const FormatException();
        }
        for (final key in ['proposedRemedy', 'reasoning', 'uncertainties']) {
          if (result[key] is! String ||
              (result[key] as String).trim().isEmpty) {
            throw const FormatException();
          }
        }
      }
      return HearingReply(model, result);
    } on JudgeException {
      rethrow;
    } on TimeoutException {
      throw const JudgeException(
        'Metherapy is taking longer than expected. Please retry this step.',
      );
    } catch (_) {
      throw const JudgeException(
        'Could not read Metherapy’s response. Your session has not changed.',
      );
    }
  }

  Future<JudgeResult> hear({
    required String topic,
    required List<String> names,
    required List<String> statements,
  }) async {
    if (!configured) {
      throw const JudgeException(
        'Metherapy AI is not connected yet. You can still try a practice conversation.',
      );
    }
    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'X-Request-ID': newRequestId(),
            },
            body: jsonEncode({
              'topic': topic,
              'names': names,
              'statements': statements,
            }),
          )
          .timeout(const Duration(seconds: 70));
      final accessError = demoErrorMessage(response.statusCode);
      if (accessError != null) throw JudgeException(accessError);
      if (response.statusCode != 200) {
        throw const JudgeException(
          'Metherapy could not respond. Your shared notes are unchanged; please try again.',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text = data['verdict'];
      final model = data['model'];
      if (text is! String ||
          text.trim().isEmpty ||
          model is! String ||
          model.isEmpty) {
        throw const FormatException();
      }
      return JudgeResult(text.trim(), model);
    } on JudgeException {
      rethrow;
    } on TimeoutException {
      throw const JudgeException(
        'Metherapy is taking longer than expected. Please try again.',
      );
    } catch (_) {
      throw const JudgeException(
        'Could not reach Metherapy. Check the connection and try again.',
      );
    }
  }
}

class JudgeException implements Exception {
  const JudgeException(this.message);
  final String message;
}

class HearingReply {
  const HearingReply(this.model, this.result);
  final String model;
  final Map<String, dynamic> result;
}
