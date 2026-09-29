import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// Phone push notifications through Firebase Cloud Messaging.
///
/// The backend sends a push alongside every in-app notification (results
/// published, marked absent, announcements, join requests). While the app is
/// in the background or closed, Android shows it in the system tray; tapping
/// it calls [onOpened]. While the app is open, nothing is shown by the system,
/// so [onForeground] is called instead.
///
/// Android only for now: iOS needs an APNs key and GoogleService-Info.plist.
/// If Firebase cannot start, push is silently disabled and the app falls
/// back to the in-app notification centre.
abstract final class PushService {
  static bool _available = false;
  static StreamSubscription<String>? _tokenRefresh;
  static const _api = NotificationService();

  /// A push arrived while the app was open.
  static void Function(RemoteMessage message)? onForeground;

  /// The user tapped a push (from the background or a closed app).
  static void Function(RemoteMessage message)? onOpened;

  /// Starts Firebase. Call once, before runApp.
  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp();
      _available = true;
    } catch (error) {
      debugPrint('Push disabled: $error');
      return;
    }
    FirebaseMessaging.onMessage.listen((m) => onForeground?.call(m));
    FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpened?.call(m));
  }

  /// Handles a push that launched the app from a closed state. Call once the
  /// navigator exists (and the user is signed in).
  static Future<void> handleLaunchMessage() async {
    if (!_available) return;
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) onOpened?.call(message);
    } catch (_) {}
  }

  /// Asks for permission (Android 13+) and sends this phone's token to the
  /// backend for the signed-in user. Safe to call on every app start.
  static Future<void> register() async {
    if (!_available) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await _api.registerDevice(token, 'android');

      _tokenRefresh ??= messaging.onTokenRefresh.listen(
        (token) => _api.registerDevice(token, 'android').catchError((_) {}),
      );
    } catch (error) {
      debugPrint('Push registration failed: $error');
    }
  }

  /// Stops pushes to this phone for the user who is signing out. Call before
  /// the session is cleared.
  static Future<void> unregister() async {
    if (!_available) return;
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null) {
        await _api
            .unregisterDevice(token)
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // Offline or already signed out on the server: deleting the token
      // below still stops pushes (the backend drops dead tokens).
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
