import 'dart:convert';

import 'api_config.dart';
import 'authed_http.dart';

/// Per-exam marking scheme (`/api/scoring-rules/:exam_id`): marks for
/// correct / wrong / blank answers, pass percentage, how ambiguous marks are
/// treated, and whether a negative total is clamped to zero.
class ScoringRulesService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<Map<String, dynamic>> saveScoringRules({
    required String examId,
    required double marksCorrect,
    required double marksWrong,
    required double marksBlank,
    required double passPercentage,
    required String ambiguousAs,
    required bool clampNegativeTotal,
  }) async {
    final response = await AuthedHttp.put(
      Uri.parse('$baseUrl/api/scoring-rules/$examId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'marks_correct': marksCorrect,
        'marks_wrong': marksWrong,
        'marks_blank': marksBlank,
        'pass_percentage': passPercentage,
        'ambiguous_as': ambiguousAs,
        'clamp_negative_total': clampNegativeTotal,
      }),
    );

    final data = decodeJsonObject(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to save scoring rules');
    }

    return Map<String, dynamic>.from(data['scoring_rules'] as Map);
  }

  /// Throws with "Scoring rules not found for this exam" (HTTP 404) when the
  /// exam has none yet.
  Future<Map<String, dynamic>> getScoringRules({required String examId}) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/scoring-rules/$examId'),
    );

    final data = decodeJsonObject(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to load scoring rules');
    }

    return Map<String, dynamic>.from(data['scoring_rules'] as Map);
  }
}
