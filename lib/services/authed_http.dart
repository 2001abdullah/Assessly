import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// HTTP helper for every call that needs a signed-in user.
///
/// It attaches the saved token as `Authorization: Bearer ...` so the server
/// knows WHICH user is asking (and returns only that user's exams, results...).
/// If the server answers 401 (token expired or invalid), [onUnauthorized] runs
/// so the app can sign the user out and show the login screen.
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

  static http.Response _check(http.Response response) {
    notifyIfUnauthorized(response.statusCode);
    return response;
  }

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) async => _check(await http.get(url, headers: await authHeaders(headers)));

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async => _check(
    await http.post(url, headers: await authHeaders(headers), body: body),
  );

  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async => _check(
    await http.put(url, headers: await authHeaders(headers), body: body),
  );

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async => _check(
    await http.delete(url, headers: await authHeaders(headers), body: body),
  );
}
