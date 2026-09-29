import 'package:google_sign_in/google_sign_in.dart';

/// Gets a Google ID token for the backend's `POST /api/auth/google`.
///
/// Needs the *Web* OAuth client ID at build time:
/// `--dart-define=GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com`
/// (the same value as the backend's GOOGLE_CLIENT_ID). On Android, Google also
/// checks that the APK's signing certificate SHA-1 is registered on an
/// Android OAuth client for package com.abdullah.assessly.
class GoogleAuthService {
  GoogleAuthService._();

  static const _serverClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static Future<void>? _initialization;

  static Future<void> _initialize() {
    if (_serverClientId.isEmpty) {
      throw Exception(
        'Google sign-in is not configured for this build '
        '(built without GOOGLE_WEB_CLIENT_ID).',
      );
    }
    return _initialization ??= GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId,
    );
  }

  static Future<String> signIn() async {
    await _initialize();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google did not return an identity token.');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      throw Exception(_describe(e));
    }
  }

  /// Turns Google's error codes into a message that says what to fix.
  static String _describe(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        // Also what Android reports when this APK's SHA-1 is not registered.
        return 'Google sign-in was cancelled. If you did not cancel it, this '
            "app build's signing key (SHA-1) is probably not registered in "
            'Google Cloud.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in is misconfigured (check the OAuth client IDs '
                'and SHA-1 fingerprints). ${e.description ?? ''}'
            .trim();
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google sign-in could not open on this device. Make sure '
            'Google Play services is installed and up to date.';
      default:
        return 'Google sign-in failed: ${e.description ?? e.code.name}';
    }
  }

  static Future<void> signOut() async {
    if (_initialization == null) return;
    await GoogleSignIn.instance.signOut();
  }
}
