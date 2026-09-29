import 'package:flutter/material.dart';

import '../services/results_service.dart';

/// Caches scored results per exam and per-question details per result.
///
/// When a new result is saved (single scan or background batch), call
/// [invalidate] and any screen showing that exam refreshes by itself.
class ResultsProvider extends ChangeNotifier {
  ResultsProvider({ResultsService? service})
    : _service = service ?? ResultsService();

  final ResultsService _service;

  final Map<String, List<Map<String, dynamic>>> _byExam = {};
  final Map<String, String> _errors = {};
  final Set<String> _loading = {};
  final Map<String, Map<String, dynamic>> _details = {};

  List<Map<String, dynamic>>? resultsFor(String examId) => _byExam[examId];
  bool isLoading(String examId) => _loading.contains(examId);
  String? errorFor(String examId) => _errors[examId];

  /// Every cached result across exams, newest first. Each row carries
  /// `exam_id` so it can be matched back to its exam.
  List<Map<String, dynamic>> get allResults {
    final all = [for (final list in _byExam.values) ...list];
    all.sort(
      (a, b) => (b['created_at']?.toString() ?? '').compareTo(
        a['created_at']?.toString() ?? '',
      ),
    );
    return all;
  }

  Future<void> loadExam(String examId, {bool force = false}) async {
    if (_loading.contains(examId)) return;
    if (!force && _byExam.containsKey(examId)) return;
    _loading.add(examId);
    _errors.remove(examId);
    notifyListeners();
    try {
      final rows = await _service.getExamResults(examId);
      _byExam[examId] = [
        for (final row in rows) {...row, 'exam_id': examId},
      ];
    } catch (e) {
      _errors[examId] = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading.remove(examId);
      notifyListeners();
    }
  }

  Future<void> loadExams(Iterable<String> examIds, {bool force = false}) =>
      Future.wait([for (final id in examIds) loadExam(id, force: force)]);

  Future<Map<String, dynamic>> details(
    String resultId, {
    bool force = false,
  }) async {
    final cached = _details[resultId];
    if (cached != null && !force) return cached;
    final details = await _service.getResultDetails(resultId);
    _details[resultId] = details;
    return details;
  }

  /// A result for [examId] was added: refresh it if anyone has loaded it.
  void invalidate(String examId) {
    if (_byExam.containsKey(examId)) {
      loadExam(examId, force: true);
    }
  }

  void removeExam(String examId) {
    _byExam.remove(examId);
    _errors.remove(examId);
    notifyListeners();
  }

  void reset() {
    _byExam.clear();
    _errors.clear();
    _loading.clear();
    _details.clear();
    notifyListeners();
  }
}
