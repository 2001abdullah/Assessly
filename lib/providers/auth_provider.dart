import 'dart:io';

import 'package:assessly/models/user_model.dart';
import 'package:assessly/services/api_service.dart';
import 'package:assessly/services/auth_service.dart';
import 'package:assessly/services/google_auth_service.dart';
import 'package:assessly/services/profile_service.dart';
import 'package:assessly/services/push_service.dart';
import 'package:flutter/material.dart';

/// Who is signed in, and the actions that change it.
///
/// Lifecycle: [restoreSession] runs on the splash screen; [login],
/// [loginWithGoogle] and [register] run from the auth screens with the role
/// chosen on the role screen; [logout] runs from the profile screen or
/// automatically when any API call returns 401 (see main.dart). Signing out
/// also clears the other providers' caches.
class AuthProvider extends ChangeNotifier {
  AuthProvider({ProfileService? profile})
    : _profile = profile ?? const ProfileService();

  final ProfileService _profile;

  bool isLoading = false;
  bool isLoggedIn = false;

  /// The signed-in user (null when signed out).
  UserModel? user;

  UserRole get role => user?.role ?? UserRole.teacher;
  bool get isStudent => user?.isStudent ?? false;

  void setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  void setLogIn(bool value) {
    isLoggedIn = value;
    notifyListeners();
  }

  Future<void> login(String login, String password, UserRole role) async {
    try {
      setLoading(true);
      final result = await ApiService.login(login, password, role: role.name);
      await _saveSession(result);
    } finally {
      setLoading(false);
    }
  }

  Future<void> loginWithGoogle(UserRole role) async {
    try {
      setLoading(true);
      final idToken = await GoogleAuthService.signIn();
      final result = await ApiService.loginWithGoogle(idToken, role: role.name);
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
      _setUser(Map<String, dynamic>.from(profile));
      await AuthService.saveUser(user!.toJson());
    } else {
      user = null;
    }
    // The login response is minimal; fetch the full profile when possible.
    try {
      await loadProfile();
    } catch (_) {
      if (user == null) rethrow;
    }
    setLogIn(true);
  }

  void _setUser(Map<String, dynamic> json) {
    user = UserModel.fromJson(json);
    notifyListeners();
  }

  /// Fetches the profile of whoever the saved token belongs to.
  Future<void> loadProfile() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) return;
    final profile = await ApiService.getProfile(token);
    _setUser(profile);
    await AuthService.saveUser(user!.toJson());
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

  Future<void> updateProfile({
    required String name,
    String? phone,
    String? institution,
    String? bio,
  }) async {
    final json = await _profile.update(
      name: name,
      phone: phone,
      institution: institution,
      bio: bio,
    );
    _setUser(json);
    await AuthService.saveUser(user!.toJson());
  }

  Future<void> changePassword({String? current, required String next}) async {
    await _profile.changePassword(current: current, next: next);
    await loadProfile();
  }

  Future<void> setAvatar(File image) async {
    _setUser(await _profile.uploadAvatar(image));
    await AuthService.saveUser(user!.toJson());
  }

  Future<void> removeAvatar() async {
    _setUser(await _profile.removeAvatar());
    await AuthService.saveUser(user!.toJson());
  }

  Future<void> logout() async {
    // Needs the session still in place to tell the backend.
    if (isLoggedIn) await PushService.unregister();
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

  Future<void> register(
    String name,
    String email,
    String password,
    UserRole role,
  ) async {
    try {
      setLoading(true);
      await ApiService.register(name, email, password, role: role.name);
    } finally {
      setLoading(false);
    }
  }
}
