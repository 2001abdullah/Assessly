import 'package:assessly/models/user_model.dart';
import 'package:assessly/services/api_service.dart';
import 'package:assessly/services/auth_service.dart';
import 'package:assessly/services/google_auth_service.dart';
import 'package:flutter/material.dart';

/// Who is signed in, and the actions that change it.
///
/// Lifecycle: [restoreSession] runs on the splash screen; [login],
/// [loginWithGoogle] and [register] run from the auth screens; [logout] runs
/// from the profile screen or automatically when any API call returns 401
/// (see main.dart). Signing out also clears the other providers' caches.
class AuthProvider extends ChangeNotifier {
  bool isLoading = false;
  bool isLoggedIn = false;

  /// The signed-in user (null when signed out).
  UserModel? user;

  void setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  void setLogIn(bool value) {
    isLoggedIn = value;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    try {
      setLoading(true);
      final result = await ApiService.login(email, password);
      await _saveSession(result);
    } finally {
      setLoading(false);
    }
  }

  Future<void> loginWithGoogle() async {
    try {
      setLoading(true);
      final idToken = await GoogleAuthService.signIn();
      final result = await ApiService.loginWithGoogle(idToken);
      await _saveSession(result);
    } finally {
      setLoading(false);
    }
  }

  /// Stores the token + profile from a login response and marks the user
  /// signed in. Falls back to `/auth/me` if the response had no profile.
  Future<void> _saveSession(Map<String, dynamic> result) async {
    final token = result['token']?.toString();
    if (token == null || token.isEmpty) {
      throw StateError('The server did not return a session token.');
    }
    await AuthService.saveToken(token);
    final profile = result['user'];
    if (profile is Map) {
      final data = Map<String, dynamic>.from(profile);
      user = UserModel.fromJson(data);
      await AuthService.saveUser(data);
    } else {
      user = null;
      await loadProfile();
    }
    setLogIn(true);
  }

  /// Fetches the profile of whoever the saved token belongs to.
  Future<void> loadProfile() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) return;
    final profile = await ApiService.getProfile(token);
    user = UserModel.fromJson(profile);
    await AuthService.saveUser(profile);
    notifyListeners();
  }

  /// Called at app start: is the saved token still valid, and whose is it?
  /// Returns false (and signs out) if the session expired.
  Future<bool> restoreSession() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      user = null;
      setLogIn(false);
      return false;
    }

    final cached = await AuthService.getUser();
    if (cached != null) user = UserModel.fromJson(cached);

    try {
      await loadProfile();
    } on SessionExpiredException {
      await logout();
      return false;
    } catch (_) {
      // Offline or server down: keep the cached profile and let the user in.
    }
    setLogIn(true);
    return true;
  }

  Future<void> logout() async {
    try {
      await GoogleAuthService.signOut();
    } catch (_) {
      // Local logout must still succeed if Google Play services is unavailable.
    }
    await AuthService.clearSession();
    user = null;
    setLogIn(false);
  }

  Future<void> deleteAccount() async {
    await ApiService.deleteAccount();
    await logout();
  }

  Future<void> register(String name, String email, String password) async {
    try {
      setLoading(true);

      await ApiService.register(name, email, password);
    } finally {
      setLoading(false);
    }
  }
}
