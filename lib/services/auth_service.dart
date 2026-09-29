import 'dart:convert';

import "package:shared_preferences/shared_preferences.dart";

/// Local session storage: the JWT and a cached copy of the user's profile.
///
/// Only persistence lives here. The sign-in flow itself is in
/// [AuthProvider]; the HTTP calls are in [ApiService].
class AuthService {
  AuthService._();

  static const String tokenKey = 'auth_token';
  static const String userKey = 'auth_user';

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(tokenKey);
  }

  /// Cached profile, so the name shows instantly (and offline) on next launch.
  static Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userKey, jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(userKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Signs out: forget the token AND the cached profile.
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
    await prefs.remove(userKey);
  }
}
