import 'dart:typed_data';

import 'api_config.dart';
import 'authed_http.dart';

/// Read side of scored results (`/api/results`). Results are created by
/// [ScoringService]; this service lists, details and exports them.
class ResultsService {
  static String get baseUrl => ApiConfig.baseUrl;

  /// Every result for an exam, best percentage first.
  Future<List<Map<String, dynamic>>> getExamResults(String examId) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/results/exam/$examId'),
    );
    final data = decodeJsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['message'] ?? 'Failed to load student results');
    }
    return List<Map<String, dynamic>>.from(data['results'] ?? const []);
  }

  /// One result with every question: given answer, correct answer, status
  /// (correct / wrong / blank / ambiguous / not_keyed) and marks.
  Future<Map<String, dynamic>> getResultDetails(String resultId) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/results/$resultId/details'),
    );
    final data = decodeJsonObject(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['result'] is! Map) {
      throw Exception(data['message'] ?? 'Failed to load result details');
    }
    return Map<String, dynamic>.from(data['result'] as Map);
  }

  /// CSV bytes (one row per student) for saving or sharing.
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
