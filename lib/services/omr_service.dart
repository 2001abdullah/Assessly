import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class OmrService {
  static String get baseUrl {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredUrl.isNotEmpty) {
      return configuredUrl;
    }

    return Platform.isAndroid
        ? 'http://10.0.2.2:5000'
        : 'http://127.0.0.1:5000';
  }

  Future<Map<String, dynamic>> scanOmr({
    required File image,
    required String examId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/omr/scan'),
    );

    request.fields['exam_id'] = examId;

    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    final streamedResponse = await request.send();

    final response = await http.Response.fromStream(streamedResponse);

    final dynamic decodedBody = jsonDecode(response.body);
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
  }
}
