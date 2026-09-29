import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Where the backend lives and how long to wait for it.
///
/// The URL is baked in at build time with
/// `--dart-define=API_BASE_URL=https://your-api.example.com`. Without it the
/// app falls back to the local development server (the Android emulator
/// reaches the host computer through 10.0.2.2).
class ApiConfig {
  ApiConfig._();

  static String get baseUrl {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredUrl.isNotEmpty) {
      return configuredUrl.replaceFirst(RegExp(r'\/+$'), '');
    }

    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:5000'
        : 'http://127.0.0.1:5000';
  }

  /// Upper bound for ordinary JSON requests. Generous because a free-tier
  /// server can take ~50 s to wake from sleep on the first request.
  static const Duration requestTimeout = Duration(seconds: 60);
}

/// Decodes a response body that should be a JSON object.
///
/// Returns an empty map for empty, non-JSON (e.g. a proxy's HTML error page)
/// or non-object bodies, so callers can always write `data['message']`.
Map<String, dynamic> decodeJsonObject(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    // Fall through: not JSON.
  }
  return <String, dynamic>{};
}

/// Applies [ApiConfig.requestTimeout] and turns a timeout into a readable
/// error. (A plain [Exception], because screens strip the "Exception: "
/// prefix before showing messages.)
Future<T> withRequestTimeout<T>(Future<T> request) {
  return request.timeout(
    ApiConfig.requestTimeout,
    onTimeout: () => throw Exception(
      'The server took too long to respond. Check your connection and try again.',
    ),
  );
}
