import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_service.dart';

/// HTTP helper for every call that needs a signed-in user.
///
/// It attaches the saved token as `Authorization: Bearer ...` so the server
/// knows WHICH user is asking (and returns only that user's exams, results...).
/// If the server answers 401 (token expired or invalid), [onUnauthorized] runs
/// so the app can sign the user out and show the login screen (see main.dart).
///
/// Every request is bounded by [ApiConfig.requestTimeout].
class AuthedHttp {
  AuthedHttp._();

  static void Function()? onUnauthorized;

  /// Headers with the current user's token merged into [extra].
  static Future<Map<String, String>> authHeaders([
    Map<String, String>? extra,
  ]) async {
    final token = await AuthService.getToken();
    return {
      ...?extra,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static void notifyIfUnauthorized(int statusCode) {
    if (statusCode == 401) onUnauthorized?.call();
  }

  static Future<http.Response> _send(Future<http.Response> request) async {
    final response = await withRequestTimeout(request);
    notifyIfUnauthorized(response.statusCode);
    return response;
  }

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) async => _send(http.get(url, headers: await authHeaders(headers)));

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async =>
      _send(http.post(url, headers: await authHeaders(headers), body: body));

  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async =>
      _send(http.put(url, headers: await authHeaders(headers), body: body));

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async =>
      _send(http.delete(url, headers: await authHeaders(headers), body: body));
}
