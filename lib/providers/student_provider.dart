import 'package:flutter/material.dart';

import '../services/student_service.dart';

/// Everything the student side shows: dashboard overview, results,
/// attendance and announcements. [refresh] reloads all of it at once.
class StudentProvider extends ChangeNotifier {
  StudentProvider({StudentService? service})
    : _service = service ?? const StudentService();

  final StudentService _service;
  StudentService get service => _service;

  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _announcements = [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  Map<String, dynamic>? get overview => _overview;
  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(_overview?['summary'] as Map? ?? const {});
  List<Map<String, dynamic>> get classes => [
    for (final c in (_overview?['classes'] as List? ?? const []))
      Map<String, dynamic>.from(c as Map),
  ];
  List<Map<String, dynamic>> get activeClasses =>
      classes.where((c) => c['status'] == 'active').toList();
  List<Map<String, dynamic>> get results => _results;
  List<Map<String, dynamic>> get attendance => _attendance;
  List<Map<String, dynamic>> get announcements => _announcements;
  bool get isLoading => _loading;
  bool get hasLoaded => _loaded;
  String? get error => _error;

  Future<void> load({bool force = false}) async {
    if (_loading || (_loaded && !force)) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _service.overview(),
        _service.results(),
        _service.attendance(),
        _service.announcements(),
      ]);
      _overview = results[0] as Map<String, dynamic>;
      _results = results[1] as List<Map<String, dynamic>>;
      _attendance = results[2] as List<Map<String, dynamic>>;
      _announcements = results[3] as List<Map<String, dynamic>>;
      _loaded = true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load(force: true);

  Future<String> joinClass(String code, String rollNumber) async {
    final message = await _service.joinClass(code, rollNumber);
    await refresh();
    return message;
  }

  Future<void> leaveClass(String classId) async {
    await _service.leaveClass(classId);
    await refresh();
  }

  void reset() {
    _overview = null;
    _results = [];
    _attendance = [];
    _announcements = [];
    _loaded = false;
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
