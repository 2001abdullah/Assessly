import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  GoogleAuthService._();

  static const _serverClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static Future<void>? _initialization;

  static Future<void> _initialize() {
    if (_serverClientId.isEmpty) {
      throw StateError('Google sign-in is not configured for this build.');
    }
    return _initialization ??= GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId,
    );
  }

  static Future<String> signIn() async {
    await _initialize();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google did not return an identity token.');
    }
    return idToken;
  }

  static Future<void> signOut() async {
    if (_initialization == null) return;
    await GoogleSignIn.instance.signOut();
  }
}
