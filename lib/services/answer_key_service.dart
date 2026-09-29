import 'dart:convert';

import 'api_config.dart';
import 'authed_http.dart';

/// Correct answers for an exam (`/api/answer-key`).
class AnswerKeyService {
  static String get baseUrl => ApiConfig.baseUrl;

  /// Replaces the exam's whole answer key with [answers]
  /// (`[{question_number: 1, correct_answer: 'A'}, ...]`). Questions left out
  /// become un-keyed and are not scored.
  Future<void> saveAnswerKey({
    required String examId,
    required List<Map<String, dynamic>> answers,
  }) async {
    final response = await AuthedHttp.post(
      Uri.parse('$baseUrl/api/answer-key/batch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'exam_id': examId, 'answers': answers}),
    );

    final data = decodeJsonObject(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to save answer key');
    }
  }

  Future<List<dynamic>> getAnswerKeys({required String examId}) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/answer-key/exam/$examId'),
    );

    final data = decodeJsonObject(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to load answer key');
    }

    return data['answer_keys'] as List<dynamic>? ?? const [];
  }
}
