import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/class_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/class_service.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/file_export.dart';
import '../../widgets/user_avatar.dart';

/// Roster of one class: join requests to approve, the enrolled students, and
/// adding a student manually (optionally with a generated login).
class ClassStudentsTab extends StatefulWidget {
  const ClassStudentsTab({super.key, required this.classData});

  final Map<String, dynamic> classData;

  @override
  State<ClassStudentsTab> createState() => _ClassStudentsTabState();
}

class _ClassStudentsTabState extends State<ClassStudentsTab> {
  final _service = const ClassService();
  late Future<List<Map<String, dynamic>>> _future = _load();
  String _query = '';

  String get _classId => widget.classData['id'].toString();

  Future<List<Map<String, dynamic>>> _load() => _service.students(_classId);

  void _reload() {
    setState(() => _future = _load());
    context.read<ClassProvider>().refresh();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddStudentSheet(classId: _classId),
    );
    if (result == null || !mounted) return;
    _reload();
    final credentials = result['credentials'];
    if (credentials is Map) {
      await showCredentials(context, Map<String, dynamic>.from(credentials));
    }
  }

  Future<void> _edit(Map<String, dynamic> s) async {
    final name = TextEditingController(text: s['name'].toString());
    final roll = TextEditingController(text: s['roll_number'].toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit student'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: roll,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Roll number'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => _service.editStudent(
        _classId,
        s['id'].toString(),
        name: name.text.trim(),
        rollNumber: roll.text.trim(),
      ),
    );
  }

  Future<void> _remove(Map<String, dynamic> s, {bool reject = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reject ? 'Decline request?' : 'Remove ${s['name']}?'),
        content: Text(
          reject ? 'They can ask again with the join code.' : 'Their attendance record in this class is deleted. Exam results stay with the exam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(reject ? 'Decline' : 'Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _service.removeStudent(_classId, s['id'].toString()));
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> s) async {
    try {
      final credentials = await _service.resetPassword(
        _classId,
        s['id'].toString(),
      );
      if (mounted) await showCredentials(context, credentials);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const [];
        final pending = all.where((s) => s['status'] == 'pending').toList();
        final q = _query.toLowerCase();
        final active = all
            .where((s) => s['status'] == 'active')
            .where(
              (s) =>
                  q.isEmpty ||
                  s['name'].toString().toLowerCase().contains(q) ||
                  s['roll_number'].toString().contains(q),
            )
            .toList();

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search name or roll',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _add,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                ErrorState(message: snapshot.error.toString(), onRetry: _reload)
              else ...[
                if (pending.isNotEmpty) ...[
                  SectionHeader(title: 'Join requests (${pending.length})'),
                  for (final s in pending)
                    _StudentTile(
                      data: s,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Decline',
                            onPressed: () => _remove(s, reject: true),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppColors.error,
                            ),
                          ),
                          IconButton.filled(
                            tooltip: 'Approve',
                            onPressed: () => _run(
                              () => _service.approve(
                                _classId,
                                s['id'].toString(),
                              ),
                            ),
                            icon: const Icon(Icons.check_rounded),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                SectionHeader(
                  title: 'Students (${all.length - pending.length})',
                ),
                if (active.isEmpty)
                  EmptyState(
                    icon: Icons.person_outline,
                    title: all.length == pending.length
                        ? 'No students yet'
                        : 'No match',
                    message: all.length == pending.length
                        ? 'Share the join code above, or add students yourself.'
                        : 'Try another name or roll number.',
                  )
                else
                  for (final s in active)
                    _StudentTile(
                      data: s,
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.studentReport,
                        arguments: {'class': widget.classData, 'student': s},
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _edit(s);
                          if (v == 'reset') _resetPassword(s);
                          if (v == 'remove') _remove(s);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit name / roll'),
                          ),
                          if (s['username'] != null)
                            const PopupMenuItem(
                              value: 'reset',
                              child: Text('Reset login password'),
                            ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove from class'),
                          ),
                        ],
                      ),
                    ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.data, this.trailing, this.onTap});

  final Map<String, dynamic> data;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rate = data['attendance_rate'];
    final hasAccount = data['has_account'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: UserAvatar(
          userId: data['user_id']?.toString(),
          name: data['name'].toString(),
          hasAvatar: data['has_avatar'] == true,
          version: data['avatar_updated_at']?.toString(),
          size: 42,
        ),
        title: Text(data['name'].toString(), style: AppTextStyles.subtitle),
        subtitle: Text(
          [
            'Roll ${data['roll_number']}',
            if (rate != null) 'Attendance $rate%',
            if (!hasAccount) 'No account',
          ].join(' • '),
        ),
        trailing: trailing,
      ),
    );
  }
}

/// Add a student by name and roll number; optionally create a login.
class _AddStudentSheet extends StatefulWidget {
  const _AddStudentSheet({required this.classId});

  final String classId;

  @override
  State<_AddStudentSheet> createState() => _AddStudentSheetState();
}

class _AddStudentSheetState extends State<_AddStudentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _roll = TextEditingController();
  bool _createLogin = true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _roll.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result = await const ClassService().addStudent(
        widget.classId,
        name: _name.text.trim(),
        rollNumber: _roll.text.trim(),
        createLogin: _createLogin,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add a student', style: AppTextStyles.title),
            const SizedBox(height: 4),
            const Text(
              'The roll number must match the one the student fills in on answer sheets.',
              style: AppTextStyles.bodySecondary,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _roll,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Roll number',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the roll number' : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _createLogin,
              onChanged: (v) => setState(() => _createLogin = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Create a login for this student'),
              subtitle: const Text(
                'For students without email. You get a username and temporary password to give them.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Add student'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a generated username + temporary password once, with copy.
Future<void> showCredentials(
  BuildContext context,
  Map<String, dynamic> credentials,
) {
  final username = credentials['username'].toString();
  final password = credentials['password'].toString();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.key_rounded, color: AppColors.primary),
      title: const Text('Student login'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Give these to the student. They sign in as a student and must choose a new password. '
            'This password is not shown again.',
            style: AppTextStyles.bodySecondary,
          ),
          const SizedBox(height: 16),
          _CredentialRow(label: 'Username', value: username),
          const SizedBox(height: 8),
          _CredentialRow(label: 'Temporary password', value: password),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(
              ClipboardData(text: 'Username: $username\nPassword: $password'),
            );
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Copied')));
          },
          child: const Text('Copy both'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        SelectableText(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}
