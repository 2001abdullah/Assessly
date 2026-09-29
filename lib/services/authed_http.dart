import 'dart:convert';

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

  static Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async =>
      _send(http.patch(url, headers: await authHeaders(headers), body: body));

  // ---------------------------------------------------------------- JSON API
  // `path` is relative to the API root, e.g. '/api/classes'. Each returns the
  // decoded JSON object, or throws an Exception with the server's message.

  static Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');
  static const _json = {'Content-Type': 'application/json'};

  static Map<String, dynamic> _decode(http.Response response) {
    final data = decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['message']?.toString() ??
            'Request failed (HTTP ${response.statusCode})',
      );
    }
    return data;
  }

  static Future<Map<String, dynamic>> getJson(String path) async =>
      _decode(await get(_uri(path)));

  static Future<Map<String, dynamic>> postJson(
    String path, [
    Object? body,
  ]) async => _decode(
    await post(_uri(path), headers: _json, body: jsonEncode(body ?? {})),
  );

  static Future<Map<String, dynamic>> putJson(
    String path, [
    Object? body,
  ]) async => _decode(
    await put(_uri(path), headers: _json, body: jsonEncode(body ?? {})),
  );

  static Future<Map<String, dynamic>> patchJson(
    String path, [
    Object? body,
  ]) async => _decode(
    await patch(_uri(path), headers: _json, body: jsonEncode(body ?? {})),
  );

  static Future<Map<String, dynamic>> deleteJson(
    String path, [
    Object? body,
  ]) async => _decode(
    await delete(_uri(path), headers: _json, body: jsonEncode(body ?? {})),
  );

  /// Raw bytes (CSV downloads, images).
  static Future<List<int>> getBytes(String path) async {
    final response = await get(_uri(path));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
    }
    return response.bodyBytes;
  }
}

/// Typed list out of a JSON response: `listOf(data['classes'])`.
List<Map<String, dynamic>> listOf(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) Map<String, dynamic>.from(item),
      ]
    : <Map<String, dynamic>>[];
