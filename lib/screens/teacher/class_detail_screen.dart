import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/class_provider.dart';
import '../../providers/exam_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/class_service.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/exam_card.dart';
import '../../widgets/file_export.dart';
import 'class_insights_tab.dart';
import 'class_students_tab.dart';

/// One class: join code, and tabs for Students, Exams, Attendance, Notices
/// and Insights (analytics + reports).
class ClassDetailScreen extends StatefulWidget {
  const ClassDetailScreen({super.key, required this.data});

  /// The class as listed; refreshed from the server on open.
  final Map<String, dynamic> data;

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  late Map<String, dynamic> _class = widget.data;
  final _service = const ClassService();

  String get _id => _class['id'].toString();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final fresh = await _service.get(_id);
      if (mounted) setState(() => _class = fresh);
    } catch (_) {}
  }

  Future<void> _edit() async {
    final updated = await Navigator.pushNamed(
      context,
      AppRoutes.editClass,
      arguments: _class,
    );
    if (updated is Map) {
      setState(
        () => _class = {..._class, ...Map<String, dynamic>.from(updated)},
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete class?'),
        content: const Text(
          'The roster, attendance and announcements are deleted. Exams and their results are kept, without a class.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ClassProvider>().delete(_id);
      if (mounted) {
        context.read<ExamProvider>().load(force: true);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _newCode() async {
    try {
      final code = await _service.newJoinCode(_id);
      setState(() => _class = {..._class, 'join_code': code});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _class['name'].toString();
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name, overflow: TextOverflow.ellipsis),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit();
                  case 'results':
                    exportFile(
                      context,
                      load: () => _service.resultsCsv(_id),
                      fileName: '$name-results.csv',
                      dialogTitle: 'Export results',
                    );
                  case 'attendance':
                    exportFile(
                      context,
                      load: () => _service.attendanceCsv(_id),
                      fileName: '$name-attendance.csv',
                      dialogTitle: 'Export attendance',
                    );
                  case 'delete':
                    _delete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit class'),
                  ),
                ),
                PopupMenuItem(
                  value: 'results',
                  child: ListTile(
                    leading: Icon(Icons.table_view_outlined),
                    title: Text('Export results (CSV)'),
                  ),
                ),
                PopupMenuItem(
                  value: 'attendance',
                  child: ListTile(
                    leading: Icon(Icons.event_note_outlined),
                    title: Text('Export attendance (CSV)'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: AppColors.error),
                    title: Text(
                      'Delete class',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Students'),
              Tab(text: 'Exams'),
              Tab(text: 'Attendance'),
              Tab(text: 'Notices'),
              Tab(text: 'Insights'),
            ],
          ),
        ),
        body: Column(
          children: [
            _JoinCodeBar(
              code: _class['join_code']?.toString() ?? '',
              meta: [
                _class['subject'],
                _class['section'],
              ].where((v) => v != null && v.toString().isNotEmpty).join(' • '),
              onNewCode: _newCode,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ClassStudentsTab(classData: _class),
                  _ExamsTab(classData: _class),
                  _AttendanceTab(classData: _class),
                  _NoticesTab(classId: _id),
                  ClassInsightsTab(classId: _id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinCodeBar extends StatelessWidget {
  const _JoinCodeBar({
    required this.code,
    required this.meta,
    required this.onNewCode,
  });

  final String code;
  final String meta;
  final VoidCallback onNewCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JOIN CODE',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primaryDark,
                  ),
                ),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: AppColors.primaryDark,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: AppTextStyles.bodySecondary.copyWith(fontSize: 12.5),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Join code copied')));
            },
            icon: const Icon(Icons.copy_rounded, color: AppColors.primaryDark),
          ),
          IconButton(
            tooltip: 'New code (the old one stops working)',
            onPressed: onNewCode,
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- exams

class _ExamsTab extends StatelessWidget {
  const _ExamsTab({required this.classData});

  final Map<String, dynamic> classData;

  @override
  Widget build(BuildContext context) {
    final exams = context.watch<ExamProvider>().forClass(
      classData['id'].toString(),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () => Navigator.pushNamed(
            context,
            AppRoutes.createNewExam,
            arguments: classData,
          ),
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('New exam for this class'),
        ),
        const SizedBox(height: 16),
        if (exams.isEmpty)
          const EmptyState(
            icon: Icons.assignment_outlined,
            title: 'No exams yet',
            message: 'Exams you create here are matched to these students by roll number.',
          )
        else
          for (final exam in exams) ...[
            ExamCard(exam: {...exam, 'class_name': null}),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

// ---------------------------------------------------------------- attendance

class _AttendanceTab extends StatefulWidget {
  const _AttendanceTab({required this.classData});

  final Map<String, dynamic> classData;

  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() => const ClassService()
      .attendanceSessions(widget.classData['id'].toString());

  Future<void> _open([String? date]) async {
    await Navigator.pushNamed(
      context,
      AppRoutes.attendance,
      arguments: {...widget.classData, 'date': ?date},
    );
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: () => _open(),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text("Take today's attendance"),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                ErrorState(
                  message: snapshot.error.toString(),
                  onRetry: () => setState(() => _future = _load()),
                )
              else if (sessions.isEmpty)
                const EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No attendance yet',
                  message: 'Mark who is present each day; students see their own record.',
                )
              else ...[
                const SectionHeader(title: 'History'),
                for (final s in sessions)
                  _SessionTile(
                    session: s,
                    onTap: () => _open(s['session_date'].toString()),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onTap});

  final Map<String, dynamic> session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final present = asInt(session['present']) + asInt(session['late']);
    final counted = present + asInt(session['absent']);
    final rate = counted == 0 ? 0.0 : present / counted;
    final date = DateTime.tryParse(session['session_date'].toString());
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: ScoreRing(
          fraction: rate,
          size: 42,
          stroke: 5,
          color: rate >= 0.75 ? AppColors.success : AppColors.warning,
          child: Text(
            '${(rate * 100).round()}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(
          date == null ? session['session_date'].toString() : formatDate(date),
        ),
        subtitle: Text(
          '$present present • ${asInt(session['absent'])} absent'
          '${asInt(session['late']) > 0 ? ' • ${asInt(session['late'])} late' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

// ---------------------------------------------------------------- notices

class _NoticesTab extends StatefulWidget {
  const _NoticesTab({required this.classId});

  final String classId;

  @override
  State<_NoticesTab> createState() => _NoticesTabState();
}

class _NoticesTabState extends State<_NoticesTab> {
  final _service = const ClassService();
  late Future<List<Map<String, dynamic>>> _future = _service.announcements(
    widget.classId,
  );

  void _reload() =>
      setState(() => _future = _service.announcements(widget.classId));

  Future<void> _compose() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(sheet).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New announcement', style: AppTextStyles.title),
            const SizedBox(height: 4),
            const Text(
              'Every student in the class is notified.',
              style: AppTextStyles.bodySecondary,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: body,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                try {
                  await _service.postAnnouncement(
                    widget.classId,
                    title.text.trim(),
                    body.text.trim(),
                  );
                  if (sheet.mounted) Navigator.pop(sheet, true);
                } catch (e) {
                  if (sheet.mounted) showError(sheet, e);
                }
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Post'),
            ),
          ],
        ),
      ),
    );
    if (posted == true) _reload();
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    try {
      await _service.deleteAnnouncement(widget.classId, a['id'].toString());
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: _compose,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Post announcement'),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                ErrorState(message: snapshot.error.toString(), onRetry: _reload)
              else if (items.isEmpty)
                const EmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'No announcements',
                  message:
                      'Share exam dates, homework or reminders with the class.',
                )
              else
                for (final a in items)
                  AnnouncementCard(data: a, onDelete: () => _delete(a)),
            ],
          ),
        );
      },
    );
  }
}

/// An announcement; shared with the student screens.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({
    super.key,
    required this.data,
    this.onDelete,
    this.showClass = false,
  });

  final Map<String, dynamic> data;
  final VoidCallback? onDelete;
  final bool showClass;

  @override
  Widget build(BuildContext context) {
    final body = data['body']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconBadge(
              icon: Icons.campaign_outlined,
              size: 38,
              color: AppColors.warning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['title'].toString(), style: AppTextStyles.subtitle),
                  const SizedBox(height: 2),
                  Text(
                    [
                          if (showClass) data['class_name'],
                          data['author_name'],
                          timeAgo(data['created_at']),
                        ]
                        .where((v) => v != null && v.toString().isNotEmpty)
                        .join(' • '),
                    style: AppTextStyles.caption,
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(body, style: AppTextStyles.body),
                  ],
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
