import 'dart:convert';
import 'dart:typed_data';

import 'api_config.dart';
import 'authed_http.dart';

class ExamService {
  static String get baseUrl => ApiConfig.baseUrl;

  // --------------------------------------------------
  // Create Exam
  // --------------------------------------------------

  Future<Map<String, dynamic>> createExam({
    required String title,
    required String subject,
    required int totalQuestions,
  }) async {
    final response = await AuthedHttp.post(
      Uri.parse('$baseUrl/api/exam'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'subject': subject,
        'total_questions': totalQuestions,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return data;
    }

    throw Exception(data['message'] ?? 'Failed to create exam');
  }

  // --------------------------------------------------
  // Get All Exams
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getExams() async {
    final response = await AuthedHttp.get(Uri.parse('$baseUrl/api/exam'));

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(data['exams']);
    }

    throw Exception(data['message'] ?? 'Failed to load exams');
  }
  // --------------------------------------------------
  // Delete Exam
  // --------------------------------------------------

  Future<void> deleteExam(String examId) async {
    final response = await AuthedHttp.delete(
      Uri.parse('$baseUrl/api/exam/$examId'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return;
    }

    throw Exception(data['message'] ?? 'Failed to delete exam');
  }

  Future<Uint8List> downloadOmrSheet(String examId) async {
    final response = await AuthedHttp.get(
      Uri.parse('$baseUrl/api/omr/exam/$examId/sheet'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to generate OMR sheet');
    }
    return response.bodyBytes;
  }
}
