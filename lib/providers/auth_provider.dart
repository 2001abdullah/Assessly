import 'package:assessly/models/user_model.dart';
import 'package:assessly/services/api_service.dart';
import 'package:assessly/services/auth_service.dart';
import 'package:flutter/material.dart';

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
      final token = result['token'];

      await AuthService.saveToken(token);

      final profile = result['user'];
      if (profile is Map<String, dynamic>) {
        user = UserModel.fromJson(profile);
        await AuthService.saveUser(profile);
      } else {
        user = null;
        await loadProfile();
      }

      setLogIn(true);
    } finally {
      setLoading(false);
    }
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
    await AuthService.clearSession();
    user = null;
    setLogIn(false);
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
