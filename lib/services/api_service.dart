import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'authed_http.dart';

/// Thrown when the server rejects the saved token (expired, invalid, user gone).
class SessionExpiredException implements Exception {
  const SessionExpiredException();

  @override
  String toString() => 'Your session has expired. Please sign in again.';
}

/// Account endpoints under `/api/auth`: register, log in (password or
/// Google), password reset, profile and account deletion.
///
/// Most of these run before the user has a token, so they use plain `http`
/// instead of [AuthedHttp]. Failures throw an [Exception] carrying the
/// server's `message`.
class ApiService {
  ApiService._();

  static String get baseUrl => '${ApiConfig.baseUrl}/api';

  static Future<http.Response> _postJson(String path, Object body) {
    return withRequestTimeout(
      http.post(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  /// Returns `{token, user: {id, name, email, role, ...}}`. [login] is an
  /// email or, for teacher-created student accounts, a username. [role] is
  /// the portal the user chose; the server refuses the other role's accounts
  /// with a message saying which portal to use.
  static Future<Map<String, dynamic>> login(
    String login,
    String password, {
    required String role,
  }) async {
    final response = await _postJson('/auth/login', {
      'email': login,
      'password': password,
      'role': role,
    });
    final data = decodeJsonObject(response.body);
    if (response.statusCode == 200) return data;
    throw Exception(data['message'] ?? 'Login failed');
  }

  /// Exchanges a Google ID token for an Assessly session (same shape as
  /// [login]). A first Google sign-in creates an account with [role].
  static Future<Map<String, dynamic>> loginWithGoogle(
    String idToken, {
    required String role,
  }) async {
    final response = await _postJson('/auth/google', {
      'id_token': idToken,
      'role': role,
    });
    final data = decodeJsonObject(response.body);
    if (response.statusCode == 200) return data;
    throw Exception(data['message'] ?? 'Google sign-in failed');
  }

  static Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password, {
    required String role,
  }) async {
    final response = await _postJson('/auth/register', {
      'name': name,
      'email': email,
      'password': password,
      'role': role,
    });
    final data = decodeJsonObject(response.body);
    if (response.statusCode == 201) return data;
    throw Exception(data['message'] ?? 'Registration failed');
  }

  /// Emails a 6-digit reset code. The server answers the same way whether or
  /// not the account exists.
  static Future<void> requestPasswordReset(String email) async {
    final response = await _postJson('/auth/forgot-password', {'email': email});
    if (response.statusCode == 202) return;
    final data = decodeJsonObject(response.body);
    throw Exception(data['message'] ?? 'Could not request password reset');
  }

  static Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final response = await _postJson('/auth/reset-password', {
      'email': email,
      'code': code,
      'password': password,
    });
    if (response.statusCode == 200) return;
    final data = decodeJsonObject(response.body);
    throw Exception(data['message'] ?? 'Could not reset password');
  }

  /// The profile (id, name, email) of the user this token belongs to.
  static Future<Map<String, dynamic>> getProfile(String token) async {
    final response = await withRequestTimeout(
      http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    if (response.statusCode == 401 || response.statusCode == 404) {
      throw const SessionExpiredException();
    }
    final data = decodeJsonObject(response.body);
    if (response.statusCode == 200 && data['user'] is Map) {
      return Map<String, dynamic>.from(data['user'] as Map);
    }
    throw Exception(data['message'] ?? 'Could not load profile');
  }

  /// Permanently deletes the signed-in account and all of its exam data.
  static Future<void> deleteAccount() async {
    final response = await AuthedHttp.delete(Uri.parse('$baseUrl/auth/me'));
    if (response.statusCode == 200 || response.statusCode == 404) return;

    final data = decodeJsonObject(response.body);
    throw Exception(data['message'] ?? 'Could not delete account');
  }
}
