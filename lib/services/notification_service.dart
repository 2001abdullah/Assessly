import 'authed_http.dart';

/// In-app notification inbox (`/api/notifications`) and push-token
/// registration.
class NotificationService {
  const NotificationService();

  /// `{notifications: [...], unread: n}`
  Future<Map<String, dynamic>> list() =>
      AuthedHttp.getJson('/api/notifications');

  Future<void> markRead(String id) =>
      AuthedHttp.postJson('/api/notifications/$id/read');

  Future<void> markAllRead() =>
      AuthedHttp.postJson('/api/notifications/read-all');

  Future<void> registerDevice(String token, String platform) =>
      AuthedHttp.postJson('/api/notifications/devices', {
        'token': token,
        'platform': platform,
      });

  Future<void> unregisterDevice(String token) =>
      AuthedHttp.deleteJson('/api/notifications/devices', {'token': token});
}
