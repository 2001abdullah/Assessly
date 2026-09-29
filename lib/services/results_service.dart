import 'dart:convert';
import 'dart:typed_data';

import 'api_config.dart';
import 'authed_http.dart';

class ResultsService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<List<Map<String, dynamic>>> getExamResults(String examId) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/results/exam/$examId'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load student results');
    }
    final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    return List<Map<String, dynamic>>.from(data['results'] ?? const []);
  }

  /// One result with every question: given answer, correct answer, status
  /// (correct / wrong / blank / ambiguous / not_keyed) and marks.
  Future<Map<String, dynamic>> getResultDetails(String resultId) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/results/$resultId/details'),
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : 'Failed to load result details',
      );
    }
    return Map<String, dynamic>.from((decoded as Map)['result'] as Map);
  }

  Future<Uint8List> downloadCsv(String examId) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/results/exam/$examId/export.csv'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to export student results');
    }
    return response.bodyBytes;
  }
}
