import 'dart:async';

import 'package:flutter/material.dart';

import '../services/notification_service.dart';

/// The in-app notification inbox and its unread badge. Polls every two
/// minutes while signed in (push notifications, once configured, make new
/// items appear sooner).
class NotificationProvider extends ChangeNotifier {
  NotificationProvider({NotificationService? service})
    : _service = service ?? const NotificationService();

  final NotificationService _service;

  List<Map<String, dynamic>> _items = [];
  int _unread = 0;
  bool _loading = false;
  Timer? _timer;

  List<Map<String, dynamic>> get items => _items;
  int get unread => _unread;
  bool get isLoading => _loading;

  void start() {
    _timer?.cancel();
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final data = await _service.list();
      _items = [
        for (final n in (data['notifications'] as List? ?? const []))
          Map<String, dynamic>.from(n as Map),
      ];
      _unread = (data['unread'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // Keep the last list; the badge is not worth an error message.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(String id) async {
    final index = _items.indexWhere((n) => n['id'] == id);
    if (index < 0 || _items[index]['read_at'] != null) return;
    _items[index] = {
      ..._items[index],
      'read_at': DateTime.now().toIso8601String(),
    };
    _unread = (_unread - 1).clamp(0, 1 << 30);
    notifyListeners();
    try {
      await _service.markRead(id);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    _items = [
      for (final n in _items) {...n, 'read_at': n['read_at'] ?? 'now'},
    ];
    _unread = 0;
    notifyListeners();
    try {
      await _service.markAllRead();
    } catch (_) {}
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _items = [];
    _unread = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
