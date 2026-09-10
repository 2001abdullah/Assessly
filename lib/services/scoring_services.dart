import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ScoringService {
  static String get baseUrl {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredUrl.isNotEmpty) {
      return configuredUrl;
    }

    return Platform.isAndroid
        ? 'http://10.0.2.2:5000'
        : 'http://127.0.0.1:5000';
  }

  Future<Map<String, dynamic>> scoreScan({
    required String examId,
    required String scanId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/scoring/score'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'exam_id': examId, 'scan_id': scanId}),
    );

    final dynamic decodedBody = jsonDecode(response.body);
    final data = decodedBody is Map<String, dynamic>
        ? decodedBody
        : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['message']?.toString() ??
            'Failed to score OMR (HTTP ${response.statusCode})',
      );
    }

    return Map<String, dynamic>.from(data);
  }
}
