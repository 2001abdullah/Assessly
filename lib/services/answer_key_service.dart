import 'dart:convert';
import 'package:http/http.dart' as http;

class AnswerKeyService {
  static const String baseUrl = 'http://10.0.2.2:5000';

  Future<void> saveAnswerKey({
    required String examId,
    required List<Map<String, dynamic>> answers,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/answer-key/batch'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'exam_id': examId,
        'answers': answers,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(
        data['message'] ?? 'Failed to save answer key',
      );
    }
  }

  Future<List<dynamic>> getAnswerKeys({
    required String examId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/answer-key/exam/$examId'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(
        data['message'] ?? 'Failed to load answer key',
      );
    }

    return data['answer_keys'];
  }
}