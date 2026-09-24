import 'dart:convert';

import 'api_config.dart';
import 'authed_http.dart';

class ScoringService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, dynamic>> scoreScan({
    required String examId,
    required String scanId,
  }) async {
    final response = await AuthedHttp.post(
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
