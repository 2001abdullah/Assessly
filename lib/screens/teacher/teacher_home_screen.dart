import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/batch_scan_provider.dart';
import '../../providers/class_provider.dart';
import '../../providers/exam_provider.dart';
import '../../routes/app_routes.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/class_picker.dart';
import '../../widgets/exam_card.dart';
import '../../widgets/exam_picker.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/user_avatar.dart';
import '../home_shell.dart';

/// Teacher dashboard: class-level numbers (classes, students, join requests,
/// today's attendance), things that need attention, quick actions, the
/// class list and recent exams.
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    await Future.wait([
      context.read<ClassProvider>().load(force: force),
      context.read<ExamProvider>().load(force: force),
    ]);
  }

  Future<void> _attendance() async {
    final cls = await pickClass(context, title: 'Take attendance for...');
    if (cls == null || !mounted) return;
    await Navigator.pushNamed(context, AppRoutes.attendance, arguments: cls);
    if (mounted) context.read<ClassProvider>().refresh();
  }

  Future<void> _scan() async {
    final exam = await pickExam(context, title: 'Scan sheets for...');
    if (exam == null || !mounted) return;
    Navigator.pushNamed(context, AppRoutes.scanOmr, arguments: exam);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final classes = context.watch<ClassProvider>();
    final exams = context.watch<ExamProvider>();
    final batch = context.watch<BatchScanProvider>();
    final s = classes.summary;
    final shell = ShellScope.of(context);

    final pending = asInt(s['pending_requests']);
    final unpublished = asInt(s['unpublished_exams']);
    final classCount = classes.classes.length;
    final takenToday = asInt(s['attendance_taken_today']);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(force: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // ---------------------------------------------------- header
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
                                _greeting(),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
                              Text(
                                user?.firstName.isNotEmpty == true
                                    ? user!.firstName
                                    : 'Teacher',
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
                          onTap: () => shell?.goTo(TeacherTab.profile),
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
                        _heroStat('$classCount', 'Classes'),
                        _heroDivider(),
                        _heroStat('${asInt(s['students'])}', 'Students'),
                        _heroDivider(),
                        _heroStat(
                          classCount == 0 ? '—' : '$takenToday/$classCount',
                          'Attendance today',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ---------------------------------------------------- attention
              if (pending > 0) ...[
                const SizedBox(height: 14),
                _Banner(
                  icon: Icons.person_add_alt_1_outlined,
                  color: AppColors.warning,
                  background: AppColors.warningSoft,
                  text:
                      '$pending ${pending == 1 ? 'student wants' : 'students want'} to join your classes',
                  onTap: () => shell?.goTo(TeacherTab.classes),
                ),
              ],
              if (unpublished > 0) ...[
                const SizedBox(height: 10),
                _Banner(
                  icon: Icons.visibility_off_outlined,
                  color: AppColors.info,
                  background: AppColors.infoSoft,
                  text:
                      '$unpublished graded ${unpublished == 1 ? 'exam is' : 'exams are'} not published to students yet',
                  onTap: () => shell?.goTo(TeacherTab.exams),
                ),
              ],
              if (batch.isProcessing || batch.failedCount > 0) ...[
                const SizedBox(height: 10),
                _BatchBanner(batch: batch),
              ],

              const SizedBox(height: 24),

              // ---------------------------------------------------- actions
              const SectionHeader(title: 'Quick actions'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
                children: [
                  _QuickAction(
                    icon: Icons.fact_check_outlined,
                    title: 'Attendance',
                    subtitle: 'Mark today',
                    color: AppColors.primary,
                    onTap: _attendance,
                  ),
                  _QuickAction(
                    icon: Icons.document_scanner_outlined,
                    title: 'Scan sheets',
                    subtitle: 'Single or batch',
                    color: AppColors.chart[1],
                    onTap: _scan,
                  ),
                  _QuickAction(
                    icon: Icons.note_add_outlined,
                    title: 'New exam',
                    subtitle: 'For a class',
                    color: AppColors.warning,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.createNewExam),
                  ),
                  _QuickAction(
                    icon: Icons.group_add_outlined,
                    title: 'New class',
                    subtitle: 'Get a join code',
                    color: AppColors.secondary,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.createClass),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              // ---------------------------------------------------- classes
              SectionHeader(
                title: 'Your classes',
                action: classCount == 0
                    ? null
                    : TextButton(
                        onPressed: () => shell?.goTo(TeacherTab.classes),
                        child: const Text('See all'),
                      ),
              ),
              if (classes.isLoading && !classes.hasLoaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (classes.error != null && classCount == 0)
                EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load classes',
                  message: classes.error!,
                  action: TextButton.icon(
                    onPressed: () => _refresh(force: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                )
              else if (classCount == 0)
                EmptyState(
                  icon: Icons.groups_2_outlined,
                  title: 'Create your first class',
                  message: 'Students join with a code, then you can take attendance and publish results.',
                  action: FilledButton.icon(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.createClass),
                    icon: const Icon(Icons.add),
                    label: const Text('New class'),
                  ),
                )
              else
                for (final c in classes.classes.take(4)) ...[
                  ClassCard(data: c),
                  const SizedBox(height: 10),
                ],

              // ---------------------------------------------------- exams
              if (exams.exams.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionHeader(
                  title: 'Recent exams',
                  action: TextButton(
                    onPressed: () => shell?.goTo(TeacherTab.exams),
                    child: const Text('See all'),
                  ),
                ),
                for (final exam in exams.exams.take(3)) ...[
                  ExamCard(exam: exam),
                  const SizedBox(height: 10),
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _heroDivider() => Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.only(right: 14),
    color: Colors.white.withValues(alpha: 0.25),
  );
}

/// One class in a list: name, subject/section, student count, today's
/// attendance and pending requests.
class ClassCard extends StatelessWidget {
  const ClassCard({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final pending = asInt(data['pending_count']);
    final today = data['attendance_today'];
    final meta = [
      data['subject'],
      data['section'],
    ].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.pushNamed(
            context,
            AppRoutes.classDetails,
            arguments: data,
          );
          if (context.mounted) context.read<ClassProvider>().refresh();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const IconBadge(icon: Icons.groups_2_outlined, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.subtitle,
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySecondary,
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusBadge(
                          label: '${asInt(data['student_count'])} students',
                          icon: Icons.person_outline,
                          color: AppColors.primaryDark,
                        ),
                        if (today != null)
                          StatusBadge(
                            label: 'Today $today%',
                            icon: Icons.event_available_outlined,
                            color: AppColors.success,
                          ),
                        if (pending > 0)
                          StatusBadge(
                            label: '$pending pending',
                            icon: Icons.hourglass_top_rounded,
                            color: AppColors.warning,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    ),
  );
}

class _BatchBanner extends StatelessWidget {
  const _BatchBanner({required this.batch});

  final BatchScanProvider batch;

  @override
  Widget build(BuildContext context) {
    final active = batch.activeCount;
    final failed = batch.failedCount;
    final processing = active > 0;
    final color = processing ? AppColors.info : AppColors.error;

    return Material(
      color: processing ? AppColors.infoSoft : AppColors.errorSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => ShellScope.of(context)?.goTo(TeacherTab.results),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (processing)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: color,
                  ),
                )
              else
                Icon(Icons.error_outline, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  processing
                      ? 'Grading $active ${active == 1 ? 'sheet' : 'sheets'} '
                            'in the background • ${batch.doneCount} saved'
                      : '$failed ${failed == 1 ? 'sheet' : 'sheets'} could not '
                            'be graded. Open the exam scan screen to retry.',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconBadge(icon: icon, color: color, size: 38),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.subtitle),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySecondary.copyWith(fontSize: 12),
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
