import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../utils/image_optimizer.dart';
import 'api_config.dart';
import 'authed_http.dart';

class OmrService {
  static String get baseUrl => ApiConfig.baseUrl;

  /// Upload + server-side scan can take a few seconds; never hang forever.
  static const Duration _timeout = Duration(seconds: 90);

  Future<Map<String, dynamic>> scanOmr({
    required File image,
    required String examId,
  }) async {
    // Big gallery photos are shrunk first (camera captures pass through).
    final File upload = await ImageOptimizer.prepareForUpload(image);

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/omr/scan'),
    );

    request.headers.addAll(await AuthedHttp.authHeaders());
    request.fields['exam_id'] = examId;

    request.files.add(await http.MultipartFile.fromPath('image', upload.path));

    try {
      final streamedResponse = await request.send().timeout(_timeout);

      final response = await http.Response.fromStream(streamedResponse)
          .timeout(_timeout);

      AuthedHttp.notifyIfUnauthorized(response.statusCode);

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(response.body);
      } on FormatException {
        decodedBody = null;
      }
      final data = decodedBody is Map<String, dynamic>
          ? decodedBody
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          data['message']?.toString() ??
              'Failed to scan OMR (HTTP ${response.statusCode})',
        );
      }

      return data;
    } on TimeoutException {
      throw Exception(
        'The server took too long to respond. Check your connection and try again.',
      );
    } finally {
      if (upload.path != image.path) {
        try {
          await upload.delete();
        } catch (_) {}
      }
    }
  }

  Future<Map<String, dynamic>> scanBatch({
    required List<File> images,
    required String examId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/omr/batch'),
    );
    request.headers.addAll(await AuthedHttp.authHeaders());
    request.fields['exam_id'] = examId;
    for (final image in images) {
      request.files.add(await http.MultipartFile.fromPath('images', image.path));
    }

    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    AuthedHttp.notifyIfUnauthorized(response.statusCode);
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded is Map ? decoded['message'] : 'Batch scan failed');
    }
    return Map<String, dynamic>.from(decoded as Map);
  }
}
