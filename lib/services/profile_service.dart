import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'authed_http.dart';

/// The signed-in user's profile (`/api/profile`): details, password and
/// profile picture.
class ProfileService {
  const ProfileService();

  Future<Map<String, dynamic>> get() async => Map<String, dynamic>.from(
    (await AuthedHttp.getJson('/api/profile'))['user'] as Map,
  );

  Future<Map<String, dynamic>> update({
    required String name,
    String? phone,
    String? institution,
    String? bio,
  }) async => Map<String, dynamic>.from(
    (await AuthedHttp.putJson('/api/profile', {
          'name': name,
          'phone': phone,
          'institution': institution,
          'bio': bio,
        }))['user']
        as Map,
  );

  Future<void> changePassword({String? current, required String next}) =>
      AuthedHttp.putJson('/api/profile/password', {
        'current_password': current ?? '',
        'new_password': next,
      });

  /// [image] should already be small (the picker resizes to 512 px).
  Future<Map<String, dynamic>> uploadAvatar(File image) async {
    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('${ApiConfig.baseUrl}/api/profile/avatar'),
    );
    request.headers.addAll(await AuthedHttp.authHeaders());
    request.files.add(await http.MultipartFile.fromPath('avatar', image.path));
    final response = await withRequestTimeout(
      request.send().then(http.Response.fromStream),
    );
    AuthedHttp.notifyIfUnauthorized(response.statusCode);
    final data = decodeJsonObject(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Could not upload the picture');
    }
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  Future<Map<String, dynamic>> removeAvatar() async =>
      Map<String, dynamic>.from(
        (await AuthedHttp.deleteJson('/api/profile/avatar'))['user'] as Map,
      );

  /// URL of a user's picture; load it with [AuthedHttp.authHeaders].
  static String avatarUrl(String userId) =>
      '${ApiConfig.baseUrl}/api/profile/avatar/$userId';
}
