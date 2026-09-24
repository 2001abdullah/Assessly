import 'dart:convert';

import 'api_config.dart';
import 'authed_http.dart';

class AnswerKeyService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<void> saveAnswerKey({
    required String examId,
    required List<Map<String, dynamic>> answers,
  }) async {
    final response = await AuthedHttp.post(
      Uri.parse('$baseUrl/api/answer-key/batch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'exam_id': examId, 'answers': answers}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to save answer key');
    }
  }

  Future<List<dynamic>> getAnswerKeys({required String examId}) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/answer-key/exam/$examId'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to load answer key');
    }

    return data['answer_keys'];
  }
}
