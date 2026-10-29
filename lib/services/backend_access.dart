import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Revocable demo access, kept in memory. Never stores the Meta API key or code.
class BackendAccess extends ChangeNotifier {
  BackendAccess({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? const String.fromEnvironment('BACKEND_URL'),
      _client = client ?? http.Client();
  static final instance = BackendAccess();
  final String baseUrl;
  final http.Client _client;
  Timer? _expiryTimer;
  String? _session;
  DateTime? _expires;
  bool get available => baseUrl.isNotEmpty;
  bool get connected =>
      _session != null &&
      _expires != null &&
      DateTime.now().isBefore(_expires!);
  String get token => connected ? _session! : '';
  DateTime? get expires => _expires;

  String url(String path) {
    if (!available) return '';
    final uri = Uri.parse(baseUrl);
    final local = {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
    if (uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && local))) {
      throw const DemoAccessException(
        'The demo backend must use a secure HTTPS address.',
      );
    }
    final root = uri.path.endsWith('/')
        ? uri
        : uri.replace(path: '${uri.path}/');
    return root.resolve(path).toString();
  }

  Future<void> connect(String code) async {
    if (!available) {
      throw const DemoAccessException(
        'The hosted demo has not been connected yet.',
      );
    }
    if (code.trim().isEmpty) {
      throw const DemoAccessException(
        'Enter the private demo code supplied with the demo.',
      );
    }
    try {
      final response = await _client
          .post(
            Uri.parse(url('auth/session')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final message = data['error'];
        throw DemoAccessException(
          message is String && message.length <= 250
              ? message
              : 'Could not connect to the AI demo.',
        );
      }
      final token = data['session_token'];
      final expiry = data['expires_at'];
      if (token is! String || token.length < 32 || expiry is! num) {
        throw const FormatException();
      }
      final expires = DateTime.fromMillisecondsSinceEpoch(
        (expiry * 1000).round(),
        isUtc: true,
      );
      if (!expires.isAfter(DateTime.now())) throw const FormatException();
      _expiryTimer?.cancel();
      _expiryTimer = Timer(expires.difference(DateTime.now()), disconnect);
      _session = token;
      _expires = expires;
      notifyListeners();
    } on DemoAccessException {
      rethrow;
    } catch (_) {
      throw const DemoAccessException(
        'Could not reach the demo. Check the connection and try again.',
      );
    }
  }

  void disconnect() {
    _expiryTimer?.cancel();
    _session = null;
    _expires = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _client.close();
    super.dispose();
  }
}

class DemoAccessException implements Exception {
  const DemoAccessException(this.message);
  final String message;
}

String newRequestId() {
  final random = Random.secure();
  return base64Url
      .encode(List<int>.generate(24, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

String defaultJudgeUrl() {
  if (!BackendAccess.instance.available) {
    return const String.fromEnvironment('JUDGE_URL');
  }
  try {
    return BackendAccess.instance.url('judge');
  } catch (_) {
    return '';
  }
}

String defaultApiToken(String endpoint) {
  if (BackendAccess.instance.available) return BackendAccess.instance.token;
  final uri = Uri.tryParse(endpoint);
  if (uri != null &&
      {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host)) {
    return const String.fromEnvironment('COURT_DEMO_TOKEN');
  }
  return '';
}

String? demoErrorMessage(int status) => switch (status) {
  401 || 403 => 'Your demo session is unavailable. Open AI demo access and enter your private demo code again.',
  409 => 'A request is already submitted or still running. Please wait before trying again.',
  429 => 'The demo is busy or its usage allowance has been reached. Please wait or contact the demo owner.',
  503 =>
    'The AI demo is currently unavailable. Practice mode remains available.',
  _ => null,
};
