import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/batch_scan_provider.dart';
import '../providers/exam_provider.dart';
import '../providers/results_provider.dart';
import '../routes/app_routes.dart';
import '../themes/app_colors.dart';
import '../themes/app_text_styles.dart';
import '../widgets/app_widgets.dart';

/// All graded sheets across the user's exams: overall stats, the latest
/// results and a per-exam breakdown.
class ResultsHubScreen extends StatefulWidget {
  const ResultsHubScreen({super.key});

  @override
  State<ResultsHubScreen> createState() => _ResultsHubScreenState();
}

class _ResultsHubScreenState extends State<ResultsHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool force = false}) async {
    final exams = context.read<ExamProvider>();
    final results = context.read<ResultsProvider>();
    await exams.load(force: force);
    await results.loadExams(
      exams.exams.map((e) => e['id'].toString()),
      force: force,
    );
  }

  @override
  Widget build(BuildContext context) {
    final examProvider = context.watch<ExamProvider>();
    final results = context.watch<ResultsProvider>();
    final batch = context.watch<BatchScanProvider>();

    final exams = examProvider.exams;
    final examIds = exams.map((e) => e['id'].toString()).toSet();
    final all = results.allResults
        .where((r) => examIds.contains(r['exam_id']))
        .toList();
    final loading =
        examProvider.isLoading ||
        exams.any((e) => results.isLoading(e['id'].toString()));

    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _OverviewHero(results: all, examCount: exams.length),
            if (batch.isProcessing) ...[
              const SizedBox(height: 14),
              _ProcessingBanner(count: batch.activeCount),
            ],
            const SizedBox(height: 24),
            if (loading && all.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (examProvider.error != null && exams.isEmpty)
              ErrorState(
                message: examProvider.error!,
                onRetry: () => _load(force: true),
              )
            else if (all.isEmpty)
              const EmptyState(
                icon: Icons.insights_outlined,
                title: 'No results yet',
                message:
                    'Scan answer sheets from an exam and every graded '
                    'sheet will appear here.',
              )
            else ...[
              const SectionHeader(title: 'Recent results'),
              for (final r in all.take(5)) ...[
                ResultRowTile(
                  result: r,
                  exam: examProvider.byId(r['exam_id'].toString()),
                  showExam: true,
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 20),
              const SectionHeader(title: 'By exam'),
              for (final exam in exams) ...[
                _ExamResultsCard(
                  exam: exam,
                  results:
                      results.resultsFor(exam['id'].toString()) ?? const [],
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _OverviewHero extends StatelessWidget {
  const _OverviewHero({required this.results, required this.examCount});

  final List<Map<String, dynamic>> results;
  final int examCount;

  @override
  Widget build(BuildContext context) {
    final count = results.length;
    final avg = count == 0
        ? 0.0
        : results
                  .map((r) => asDouble(r['percentage']))
                  .reduce((a, b) => a + b) /
              count;
    final passed = results.where((r) => r['passed'] == true).length;
    final passRate = count == 0 ? 0.0 : passed * 100 / count;

    return HeroPanel(
      child: Row(
        children: [
          ScoreRing(
            fraction: avg / 100,
            color: Colors.white,
            trackColor: Colors.white.withValues(alpha: 0.2),
            size: 104,
            stroke: 9,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${avg.round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'average',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heroStat('$count', 'sheets graded'),
                const SizedBox(height: 10),
                _heroStat('${passRate.round()}%', 'pass rate'),
                const SizedBox(height: 10),
                _heroStat('$examCount', examCount == 1 ? 'exam' : 'exams'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        TextSpan(
          text: '  $label',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
      ],
    ),
    style: const TextStyle(color: Colors.white),
  );
}

class _ProcessingBanner extends StatelessWidget {
  const _ProcessingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.info,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Grading $count ${count == 1 ? 'sheet' : 'sheets'} in the '
              'background. Results appear here automatically.',
              style: const TextStyle(
                color: AppColors.info,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamResultsCard extends StatelessWidget {
  const _ExamResultsCard({required this.exam, required this.results});

  final Map<String, dynamic> exam;
  final List<Map<String, dynamic>> results;

  @override
  Widget build(BuildContext context) {
    final count = results.length;
    final avg = count == 0
        ? 0.0
        : results
                  .map((r) => asDouble(r['percentage']))
                  .reduce((a, b) => a + b) /
              count;
    final passed = results.where((r) => r['passed'] == true).length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.studentResults,
          arguments: exam,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconBadge(icon: Icons.description_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exam['title']?.toString() ?? 'Exam',
                          style: AppTextStyles.subtitle,
                        ),
                        Text(
                          count == 0
                              ? 'No sheets graded yet'
                              : '$count graded • $passed passed',
                          style: AppTextStyles.bodySecondary,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    count == 0 ? '—' : '${avg.round()}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: count == 0
                          ? AppColors.textSecondary
                          : scoreColor(avg),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (count > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: avg / 100,
                    minHeight: 6,
                    color: scoreColor(avg),
                    backgroundColor: AppColors.surfaceMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One student's result in a list. Tapping opens the per-question view.
class ResultRowTile extends StatelessWidget {
  const ResultRowTile({
    super.key,
    required this.result,
    this.exam,
    this.rank,
    this.showExam = false,
  });

  final Map<String, dynamic> result;
  final Map<String, dynamic>? exam;
  final int? rank;
  final bool showExam;

  @override
  Widget build(BuildContext context) {
    final pct = asDouble(result['percentage']);
    final passed = result['passed'] == true;
    final color = scoreColor(pct, passed: passed);
    final roll = formatIdentifier(result['roll_number']);
    final reg = formatIdentifier(result['registration_number']);
    final secondLine = showExam
        ? '${exam?['title'] ?? 'Exam'} • ${timeAgo(result['created_at'])}'
        : 'Reg. $reg • ${timeAgo(result['created_at'])}';

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.result,
          arguments: {'resultId': result['result_id'], 'exam': exam},
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              if (rank != null) ...[
                SizedBox(
                  width: 26,
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: rank! <= 3
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              ScoreRing(
                fraction: pct / 100,
                color: color,
                size: 46,
                stroke: 4.5,
                child: Text(
                  '${pct.round()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Roll $roll', style: AppTextStyles.subtitle),
                    const SizedBox(height: 2),
                    Text(
                      secondLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySecondary,
                    ),
                    if (result['needs_review'] == true) ...[
                      const SizedBox(height: 4),
                      const StatusBadge(
                        label: 'Needs review',
                        icon: Icons.flag_outlined,
                        color: AppColors.warning,
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    result['grade']?.toString() ?? '-',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    '${formatNumber(asDouble(result['marks']))}/'
                    '${formatNumber(asDouble(result['max_marks']))}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
