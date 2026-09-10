import 'dart:convert';
import 'package:http/http.dart' as http;

class ExamService {
  static const String baseUrl = 'http://10.0.2.2:5000';

  // --------------------------------------------------
  // Create Exam
  // --------------------------------------------------

  Future<Map<String, dynamic>> createExam({
    required String title,
    required String subject,
    required int totalQuestions,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/exam'),
      headers: {
        'Content-Type': 'application/json',
      },
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

    throw Exception(
      data['message'] ?? 'Failed to create exam',
    );
  }

  // --------------------------------------------------
  // Get All Exams
  // --------------------------------------------------

  Future<List<Map<String, dynamic>>> getExams() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/exam'),
    );



    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(
        data['exams'],
      );
    }

    throw Exception(
      data['message'] ?? 'Failed to load exams',
    );
  }
  // --------------------------------------------------
// Delete Exam
// --------------------------------------------------

  Future<void> deleteExam(String examId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/exam/$examId'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return;
    }

    throw Exception(
      data['message'] ?? 'Failed to delete exam',
    );
  }
}