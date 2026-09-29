import 'dart:convert';

import 'api_config.dart';
import 'authed_http.dart';

/// Scores a stored OMR scan against its exam's answer key and scoring rules
/// (`POST /api/scoring/score`). The server saves the result and returns
/// `{result_id, result: {...marks, grade, passed...}}`.
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

    final data = decodeJsonObject(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['message']?.toString() ??
            'Failed to score OMR (HTTP ${response.statusCode})',
      );
    }

    return data;
  }
}
