import 'dart:convert';
import 'package:http/http.dart' as http;

class ScoringRulesService {
  static const String baseUrl = 'http://10.0.2.2:5000';

  Future<Map<String, dynamic>> saveScoringRules({
    required String examId,
    required double marksCorrect,
    required double marksWrong,
    required double marksBlank,
    required double passPercentage,
    required String ambiguousAs,
    required bool clampNegativeTotal,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/scoring-rules/$examId'),
      headers: {
        'Content-Type': 'application/json',
      },
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
      throw Exception(
        data['message'] ?? 'Failed to save scoring rules',
      );
    }

    return data['scoring_rules'];
  }

  Future<Map<String, dynamic>> getScoringRules({
    required String examId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/scoring-rules/$examId'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(
        data['message'] ?? 'Failed to load scoring rules',
      );
    }

    return data['scoring_rules'];
  }
}