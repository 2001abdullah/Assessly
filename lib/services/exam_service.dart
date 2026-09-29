import 'dart:convert';
import 'dart:typed_data';

import 'api_config.dart';
import 'authed_http.dart';

/// Exam CRUD (`/api/exam`) and printable OMR sheet download.
///
/// Screens normally go through [ExamProvider], which caches the list; use
/// this directly only for one-off calls such as [downloadOmrSheet].
class ExamService {
  static String get baseUrl => ApiConfig.baseUrl;

  /// Returns `{message, exam: {...}}`.
  Future<Map<String, dynamic>> createExam({
    required String title,
    required String subject,
    required int totalQuestions,
    required int rollDigits,
    required int registrationDigits,
  }) async {
    final response = await AuthedHttp.post(
      Uri.parse('$baseUrl/api/exam'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'subject': subject,
        'total_questions': totalQuestions,
        'roll_digits': rollDigits,
        'registration_digits': registrationDigits,
      }),
    );

    final data = decodeJsonObject(response.body);

    if (response.statusCode == 201) return data;

    throw Exception(data['message'] ?? 'Failed to create exam');
  }

  /// The signed-in user's exams, newest first.
  Future<List<Map<String, dynamic>>> getExams() async {
    final response = await AuthedHttp.get(Uri.parse('$baseUrl/api/exam'));

    final data = decodeJsonObject(response.body);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(data['exams'] ?? const []);
    }

    throw Exception(data['message'] ?? 'Failed to load exams');
  }

  /// Deletes the exam and (by database cascade) its answer key, rules,
  /// scans and results.
  Future<void> deleteExam(String examId) async {
    final response = await AuthedHttp.delete(
      Uri.parse('$baseUrl/api/exam/$examId'),
    );

    if (response.statusCode == 200) return;

    final data = decodeJsonObject(response.body);
    throw Exception(data['message'] ?? 'Failed to delete exam');
  }

  /// PDF bytes of the answer sheet generated for this exam's layout.
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
