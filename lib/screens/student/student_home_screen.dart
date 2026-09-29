import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/student_provider.dart';
import '../../routes/app_routes.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/file_export.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/user_avatar.dart';
import '../home_shell.dart';
import '../teacher/class_detail_screen.dart' show AnnouncementCard;

/// Student dashboard: headline numbers, classes (and pending requests),
/// latest announcements and recent results.
class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<StudentProvider>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final student = context.watch<StudentProvider>();
    final s = student.summary;
    final shell = ShellScope.of(context);
    final classes = student.classes;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: student.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              HeroPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
                              Text(
                                user?.firstName.isNotEmpty == true
                                    ? user!.firstName
                                    : 'Student',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const NotificationBell(onDark: true),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => shell?.goTo(StudentTab.profile),
                          customBorder: const CircleBorder(),
                          child: UserAvatar(
                            userId: user?.id,
                            name: user?.name ?? '',
                            hasAvatar: user?.hasAvatar ?? false,
                            version: user?.avatarUpdatedAt,
                            size: 42,
                            ring: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        _heroStat(
                          s['average'] == null
                              ? '—'
                              : '${formatNumber(asDouble(s['average']))}%',
                          'Average',
                        ),
                        _divider(),
                        _heroStat('${asInt(s['exams_taken'])}', 'Exams'),
                        _divider(),
                        _heroStat(
                          s['attendance_rate'] == null
                              ? '—'
                              : '${formatNumber(asDouble(s['attendance_rate']))}%',
                          'Attendance',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (student.isLoading && !student.hasLoaded)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (student.error != null && !student.hasLoaded)
                ErrorState(message: student.error!, onRetry: student.refresh)
              else ...[
                SectionHeader(
                  title: 'My classes',
                  action: TextButton.icon(
                    onPressed: () => showJoinClassSheet(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Join'),
                  ),
                ),
                if (classes.isEmpty)
                  EmptyState(
                    icon: Icons.groups_2_outlined,
                    title: 'Join your class',
                    message: 'Ask your teacher for the class code, then enter it with your roll number.',
                    action: FilledButton.icon(
                      onPressed: () => showJoinClassSheet(context),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Enter class code'),
                    ),
                  )
                else
                  for (final c in classes) _ClassTile(data: c),
                if (student.announcements.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const SectionHeader(title: 'Announcements'),
                  for (final a in student.announcements.take(3))
                    AnnouncementCard(data: a, showClass: true),
                ],
                if (student.results.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionHeader(
                    title: 'Latest results',
                    action: TextButton(
                      onPressed: () => shell?.goTo(StudentTab.results),
                      child: const Text('See all'),
                    ),
                  ),
                  for (final r in student.results.take(3))
                    MyResultCard(data: r),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroStat(String value, String label) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _divider() => Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.only(right: 14),
    color: Colors.white.withValues(alpha: 0.25),
  );
}

class _ClassTile extends StatelessWidget {
  const _ClassTile({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final pending = data['status'] == 'pending';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: IconBadge(
          icon: pending ? Icons.hourglass_top_rounded : Icons.groups_2_outlined,
          color: pending ? AppColors.warning : AppColors.primary,
          size: 42,
        ),
        title: Text(
          data['class_name'].toString(),
          style: AppTextStyles.subtitle,
        ),
        subtitle: Text(
          [
            if (data['subject'] != null) data['subject'],
            'Roll ${data['roll_number']}',
            data['teacher_name'],
          ].where((v) => v != null).join(' • '),
        ),
        trailing: pending
            ? const StatusBadge(label: 'Waiting', color: AppColors.warning)
            : PopupMenuButton<String>(
                onSelected: (_) async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text('Leave ${data['class_name']}?'),
                      content: const Text(
                        'You will stop seeing its results and announcements. You can join again with the code.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('Leave'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    try {
                      await context.read<StudentProvider>().leaveClass(
                        data['class_id'].toString(),
                      );
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'leave', child: Text('Leave class')),
                ],
              ),
      ),
    );
  }
}

/// One published result: exam, class, score, grade and rank.
class MyResultCard extends StatelessWidget {
  const MyResultCard({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final pct = asDouble(data['percentage']);
    final passed = data['passed'] as bool?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.result,
          arguments: {'resultId': data['result_id'], 'forStudent': true},
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ScoreRing(
                fraction: pct / 100,
                size: 54,
                stroke: 6,
                color: scoreColor(pct, passed: passed),
                child: Text(
                  data['grade']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['exam_title'].toString(),
                      style: AppTextStyles.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        data['class_name'],
                        shortDate(data['date']),
                      ].where((v) => v != null && v != '').join(' • '),
                      style: AppTextStyles.bodySecondary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rank ${asInt(data['rank'])} of ${asInt(data['out_of'])} • class avg ${formatNumber(asDouble(data['class_average']))}%',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatNumber(pct)}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: scoreColor(pct, passed: passed),
                    ),
                  ),
                  Text(
                    '${formatNumber(asDouble(data['marks']))}/${formatNumber(asDouble(data['max_marks']))}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Class code + roll number form. Used on the home and profile screens.
Future<void> showJoinClassSheet(BuildContext context) async {
  final code = TextEditingController();
  final roll = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var busy = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(sheet).viewInsets.bottom + 20,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Join a class', style: AppTextStyles.title),
              const SizedBox(height: 4),
              const Text(
                'Use the roll number you write on answer sheets so your results are matched to you.',
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: code,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                style: const TextStyle(
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  labelText: 'Class code',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
                validator: (v) => (v ?? '').trim().length < 4
                    ? 'Enter the code from your teacher'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: roll,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Your roll number',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter your roll number' : null,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setSheet(() => busy = true);
                        try {
                          final message = await sheet
                              .read<StudentProvider>()
                              .joinClass(code.text, roll.text);
                          if (sheet.mounted) {
                            Navigator.pop(sheet);
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(message)));
                          }
                        } catch (e) {
                          if (sheet.mounted) showError(sheet, e);
                        } finally {
                          if (sheet.mounted) setSheet(() => busy = false);
                        }
                      },
                child: busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send request'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
