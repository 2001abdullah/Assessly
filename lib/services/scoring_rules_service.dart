import 'dart:convert';

import 'api_config.dart';
import 'authed_http.dart';

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

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to save scoring rules');
    }

    return data['scoring_rules'];
  }

  Future<Map<String, dynamic>> getScoringRules({required String examId}) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/scoring-rules/$examId'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to load scoring rules');
    }

    return data['scoring_rules'];
  }
}
