import 'package:flutter/material.dart';

import '../services/class_service.dart';

/// The teacher's classes and home-screen dashboard. Screens that change a
/// class (create, roster, attendance) call [refresh] so counts stay current.
class ClassProvider extends ChangeNotifier {
  ClassProvider({ClassService? service})
    : _service = service ?? const ClassService();

  final ClassService _service;
  ClassService get service => _service;

  List<Map<String, dynamic>> _classes = [];
  Map<String, dynamic>? _dashboard;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<Map<String, dynamic>> get classes => List.unmodifiable(_classes);
  Map<String, dynamic>? get dashboard => _dashboard;
  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(_dashboard?['summary'] as Map? ?? const {});
  bool get isLoading => _loading;
  bool get hasLoaded => _loaded;
  String? get error => _error;

  Map<String, dynamic>? byId(String classId) {
    for (final c in _classes) {
      if (c['id']?.toString() == classId) return c;
    }
    return null;
  }

  /// Loads the dashboard (which includes the class list) once; pass [force]
  /// to refresh.
  Future<void> load({bool force = false}) async {
    if (_loading || (_loaded && !force)) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _dashboard = await _service.dashboard();
      _classes = [
        for (final c in (_dashboard!['classes'] as List? ?? const []))
          Map<String, dynamic>.from(c as Map),
      ];
      _loaded = true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load(force: true);

  Future<Map<String, dynamic>> create({
    required String name,
    String? subject,
    String? section,
    String? description,
  }) async {
    final created = await _service.create(
      name: name,
      subject: subject,
      section: section,
      description: description,
    );
    await refresh();
    return created;
  }

  Future<void> delete(String classId) async {
    await _service.delete(classId);
    await refresh();
  }

  void reset() {
    _classes = [];
    _dashboard = null;
    _loaded = false;
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
