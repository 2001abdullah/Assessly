import 'package:flutter/material.dart';

import '../services/exam_service.dart';

/// Single source of truth for the signed-in user's exams.
///
/// Every screen that lists exams reads from here, so creating or deleting an
/// exam anywhere is reflected everywhere immediately.
class ExamProvider extends ChangeNotifier {
  ExamProvider({ExamService? service}) : _service = service ?? ExamService();

  final ExamService _service;

  List<Map<String, dynamic>> _exams = [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<Map<String, dynamic>> get exams => List.unmodifiable(_exams);
  bool get isLoading => _loading;
  bool get hasLoaded => _loaded;
  String? get error => _error;

  Map<String, dynamic>? byId(String examId) {
    for (final exam in _exams) {
      if (exam['id']?.toString() == examId) return exam;
    }
    return null;
  }

  /// Loads exams once; pass [force] to refresh from the server.
  Future<void> load({bool force = false}) async {
    if (_loading || (_loaded && !force)) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _exams = await _service.getExams();
      _loaded = true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> create({
    required String title,
    required String subject,
    required int totalQuestions,
    required int rollDigits,
    required int registrationDigits,
    String? classId,
  }) async {
    final response = await _service.createExam(
      title: title,
      subject: subject,
      totalQuestions: totalQuestions,
      rollDigits: rollDigits,
      registrationDigits: registrationDigits,
      classId: classId,
    );
    final exam = response['exam'];
    if (exam is Map) {
      _exams = [Map<String, dynamic>.from(exam), ..._exams];
      notifyListeners();
      return Map<String, dynamic>.from(exam);
    }
    await load(force: true);
    return Map<String, dynamic>.from(response);
  }

  /// Removes the exam locally right away and restores it if the server
  /// refuses.
  Future<void> delete(String examId) async {
    final index = _exams.indexWhere((e) => e['id']?.toString() == examId);
    if (index < 0) return;
    final removed = _exams[index];
    _exams = [..._exams]..removeAt(index);
    notifyListeners();
    try {
      await _service.deleteExam(examId);
    } catch (e) {
      _exams = [..._exams]..insert(index, removed);
      notifyListeners();
      rethrow;
    }
  }

  /// Publishes or hides an exam's results for its class's students.
  Future<void> setPublished(String examId, bool published) async {
    final publishedAt = await _service.setPublished(examId, published);
    _exams = [
      for (final e in _exams)
        e['id']?.toString() == examId
            ? {...e, 'results_published_at': publishedAt}
            : e,
    ];
    notifyListeners();
  }

  /// Exams of one class, from the cached list.
  List<Map<String, dynamic>> forClass(String classId) =>
      _exams.where((e) => e['class_id']?.toString() == classId).toList();

  void reset() {
    _exams = [];
    _loaded = false;
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
