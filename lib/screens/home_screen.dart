import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/providers/batch_scan_provider.dart';
import 'package:assessly/providers/exam_provider.dart';
import 'package:assessly/providers/results_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:assessly/widgets/app_widgets.dart';
import 'package:assessly/widgets/exam_card.dart';
import 'package:assessly/widgets/exam_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Dashboard: greeting, recent exams, quick actions and background-scan status.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// Exams come from [ExamProvider], so exams created or deleted on any
  /// screen show up here without a manual reload.
  Future<void> _refresh({bool force = false}) async {
    final exams = context.read<ExamProvider>();
    final results = context.read<ResultsProvider>();
    await exams.load(force: force);
    await results.loadExams(
      exams.exams.map((e) => e['id'].toString()),
      force: force,
    );
  }

  Future<void> _withExam(String title, String route) async {
    final exam = await pickExam(context, title: title);
    if (exam == null || !mounted) return;
    Navigator.pushNamed(context, route, arguments: exam);
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
    final firstName = user?.firstName ?? '';
    final examProvider = context.watch<ExamProvider>();
    final results = context.watch<ResultsProvider>();
    final batch = context.watch<BatchScanProvider>();

    final exams = examProvider.exams;
    final examIds = exams.map((e) => e['id'].toString()).toSet();
    final graded = results.allResults
        .where((r) => examIds.contains(r['exam_id']))
        .toList();
    final avg = graded.isEmpty
        ? null
        : graded.map((r) => asDouble(r['percentage'])).reduce((a, b) => a + b) /
              graded.length;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(force: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // ------------------------------------------------ header
              HeroPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.fact_check_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Assessly',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.profile),
                          borderRadius: BorderRadius.circular(24),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white,
                            child: Text(
                              firstName.isEmpty
                                  ? '?'
                                  : firstName[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      firstName.isEmpty
                          ? '${_greeting()}!'
                          : '${_greeting()}, $firstName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Grade answer sheets in seconds.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _heroStat('${exams.length}', 'Exams'),
                        _heroDivider(),
                        _heroStat('${graded.length}', 'Graded'),
                        _heroDivider(),
                        _heroStat(
                          avg == null ? '—' : '${avg.round()}%',
                          'Average',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ------------------------------------------------ batch banner
              if (batch.isProcessing || batch.failedCount > 0) ...[
                const SizedBox(height: 14),
                _BatchBanner(batch: batch),
              ],

              const SizedBox(height: 20),

              // ------------------------------------------------ create
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.createNewExam),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create new exam'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),

              const SizedBox(height: 28),

              // ------------------------------------------------ quick actions
              const SectionHeader(title: 'Quick actions'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  _QuickAction(
                    icon: Icons.document_scanner_outlined,
                    title: 'Scan sheets',
                    subtitle: 'Single or batch',
                    color: AppColors.primary,
                    onTap: () =>
                        _withExam('Scan sheets for...', AppRoutes.scanOmr),
                  ),
                  _QuickAction(
                    icon: Icons.insights_outlined,
                    title: 'Results',
                    subtitle: '${graded.length} graded',
                    color: AppColors.success,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.results),
                  ),
                  _QuickAction(
                    icon: Icons.folder_open_outlined,
                    title: 'Exams',
                    subtitle: 'Manage all',
                    color: AppColors.secondary,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.exams),
                  ),
                  _QuickAction(
                    icon: Icons.key_outlined,
                    title: 'Answer keys',
                    subtitle: 'Set correct answers',
                    color: AppColors.warning,
                    onTap: () =>
                        _withExam('Answer key for...', AppRoutes.answerKey),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ------------------------------------------------ exams
              SectionHeader(
                title: 'Your exams',
                action: exams.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRoutes.exams),
                        child: const Text('See all'),
                      ),
              ),
              _buildRecentExams(examProvider, results),
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

  Widget _heroDivider() => Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.only(right: 16),
    color: Colors.white.withValues(alpha: 0.25),
  );

  Widget _buildRecentExams(ExamProvider provider, ResultsProvider results) {
    if (provider.isLoading && !provider.hasLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.error != null && provider.exams.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load exams',
        message: provider.error!,
        action: TextButton.icon(
          onPressed: () => _refresh(force: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }

    if (provider.exams.isEmpty) {
      return const EmptyState(
        icon: Icons.assignment_outlined,
        title: 'No exams yet',
        message: 'Create your first exam to get started.',
      );
    }

    return Column(
      children: [
        for (final exam in provider.exams.take(3)) ...[
          ExamCard(
            exam: exam,
            gradedCount: results.resultsFor(exam['id'].toString())?.length,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
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
        onTap: () => Navigator.pushNamed(context, AppRoutes.results),
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
              IconBadge(icon: icon, color: color, size: 40),
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
