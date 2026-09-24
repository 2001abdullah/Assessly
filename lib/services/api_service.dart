import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

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

  static Future<void> testAuthenticatedConnection(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    print(response.statusCode);
    print(response.body);
  }
}
