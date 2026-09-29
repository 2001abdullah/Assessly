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

class ApiService {
  static String get baseUrl => '${ApiConfig.baseUrl}/api';
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': "application/json"},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data["message"]);
    }
  }

  static Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(data['message'] ?? 'Google sign-in failed');
  }

  static Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': "application/json"},
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return data;
    } else {
      throw Exception(data['message']);
    }
  }

  static Future<void> requestPasswordReset(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode == 202) return;
    final data = jsonDecode(response.body);
    throw Exception(data['message'] ?? 'Could not request password reset');
  }

  static Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code, 'password': password}),
    );
    if (response.statusCode == 200) return;
    final data = jsonDecode(response.body);
    throw Exception(data['message'] ?? 'Could not reset password');
  }

  /// The profile (id, name, email) of the user this token belongs to.
  static Future<Map<String, dynamic>> getProfile(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 401 || response.statusCode == 404) {
      throw const SessionExpiredException();
    }
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['user'] is Map) {
      return Map<String, dynamic>.from(data['user'] as Map);
    }
    throw Exception(data['message'] ?? 'Could not load profile');
  }

  /// Permanently deletes the signed-in account and all of its exam data.
  static Future<void> deleteAccount() async {
    final response = await AuthedHttp.delete(Uri.parse('$baseUrl/auth/me'));
    if (response.statusCode == 200 || response.statusCode == 404) return;

    final data = jsonDecode(response.body);
    throw Exception(data['message'] ?? 'Could not delete account');
  }
}
