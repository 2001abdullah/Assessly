import 'package:flutter/material.dart';

import '../../services/class_service.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/file_export.dart';

/// Take or edit one day's attendance for a class.
///
/// Everyone starts as Present (or as saved, when editing a day); tap a
/// student's status to cycle it, or use "Mark all". Students marked absent are
/// notified once when saved.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.classData});

  /// The class; may carry `date` (YYYY-MM-DD) to open that day.
  final Map<String, dynamic> classData;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

const _statuses = ['present', 'absent', 'late', 'excused'];

Color attendanceColor(String status) => switch (status) {
  'present' => AppColors.success,
  'absent' => AppColors.error,
  'late' => AppColors.warning,
  _ => AppColors.info,
};

String attendanceLabel(String status) =>
    status[0].toUpperCase() + status.substring(1);

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _service = const ClassService();
  late DateTime _day =
      DateTime.tryParse(widget.classData['date']?.toString() ?? '') ??
      DateTime.now();
  List<Map<String, dynamic>> _roster = [];
  final Map<String, String> _status = {};
  final _note = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _taken = false;
  String? _error;

  String get _classId => widget.classData['id'].toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.attendanceFor(_classId, _day);
      _roster = [
        for (final r in data['records'] as List)
          Map<String, dynamic>.from(r as Map),
      ];
      _status
        ..clear()
        ..addAll({
          for (final r in _roster)
            r['student_id'].toString(): (r['status'] ?? 'present').toString(),
        });
      _taken = data['taken'] == true;
      _note.text = data['note']?.toString() ?? '';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _day = picked);
      _load();
    }
  }

  void _cycle(String id) {
    final next =
        _statuses[(_statuses.indexOf(_status[id] ?? 'present') + 1) %
            _statuses.length];
    setState(() => _status[id] = next);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.saveAttendance(
        _classId,
        _day,
        _status,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance saved for ${formatDate(_day, weekday: false)}',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = {
      for (final s in _statuses) s: _status.values.where((v) => v == s).length,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.classData['name']?.toString() ?? 'Attendance'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Mark all',
            icon: const Icon(Icons.done_all_rounded),
            onSelected: (s) => setState(() {
              for (final key in _status.keys) {
                _status[key] = s;
              }
            }),
            itemBuilder: (_) => [
              for (final s in _statuses)
                PopupMenuItem(
                  value: s,
                  child: Text('Mark all ${attendanceLabel(s).toLowerCase()}'),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _roster.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_taken ? 'Update attendance' : 'Save attendance'),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: ListTile(
                    onTap: _pickDay,
                    leading: const IconBadge(
                      icon: Icons.calendar_today_outlined,
                      size: 40,
                    ),
                    title: Text(
                      formatDate(_day),
                      style: AppTextStyles.subtitle,
                    ),
                    subtitle: Text(
                      _taken ? 'Already taken — editing' : 'Not taken yet',
                    ),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final s in _statuses)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: attendanceColor(s).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${counts[s]}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: attendanceColor(s),
                                  ),
                                ),
                                Text(
                                  attendanceLabel(s),
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_roster.isEmpty)
                  const EmptyState(
                    icon: Icons.person_off_outlined,
                    title: 'No students in this class',
                    message: 'Add students or approve join requests first.',
                  )
                else ...[
                  const Text(
                    'Tap a status to change it',
                    style: AppTextStyles.bodySecondary,
                  ),
                  const SizedBox(height: 8),
                  for (final r in _roster)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _cycle(r['student_id'].toString()),
                        title: Text(
                          r['name'].toString(),
                          style: AppTextStyles.subtitle,
                        ),
                        subtitle: Text('Roll ${r['roll_number']}'),
                        trailing: _StatusChip(
                          status:
                              _status[r['student_id'].toString()] ?? 'present',
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _note,
                    decoration: const InputDecoration(
                      labelText: 'Note for this day (optional)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = attendanceColor(status);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 88,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        attendanceLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
