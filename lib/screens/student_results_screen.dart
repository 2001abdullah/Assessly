import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/batch_scan_provider.dart';
import '../providers/results_provider.dart';
import '../services/results_service.dart';
import '../themes/app_colors.dart';
import '../themes/app_text_styles.dart';
import '../widgets/app_widgets.dart';
import 'results_hub_screen.dart';

/// Every student's result for one exam, with summary statistics and CSV export.
class StudentResultsScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const StudentResultsScreen({super.key, required this.exam});

  @override
  State<StudentResultsScreen> createState() => _StudentResultsScreenState();
}

class _StudentResultsScreenState extends State<StudentResultsScreen> {
  final ResultsService _service = ResultsService();
  String _query = '';

  String get _examId => widget.exam['id'].toString();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ResultsProvider>().loadExam(_examId, force: true),
    );
  }

  Future<void> _export() async {
    try {
      final bytes = await _service.downloadCsv(_examId);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Export student results',
        fileName: '${widget.exam['title']}-results.csv',
        bytes: bytes,
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ResultsProvider>();
    final processing = context
        .watch<BatchScanProvider>()
        .jobsFor(_examId)
        .where((j) => j.isActive)
        .length;
    final results = provider.resultsFor(_examId);
    final error = provider.errorFor(_examId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student results'),
        actions: [
          IconButton(
            onPressed: _export,
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (results == null && error != null) {
            return ErrorState(
              message: error,
              onRetry: () => provider.loadExam(_examId, force: true),
            );
          }
          if (results == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final q = _query.trim().toLowerCase();
          final visible = q.isEmpty
              ? results
              : results.where((r) {
                  final roll = formatIdentifier(r['roll_number']).toLowerCase();
                  final reg = formatIdentifier(r['registration_number'])
                      .toLowerCase();
                  return roll.contains(q) || reg.contains(q);
                }).toList();

          return RefreshIndicator(
            onRefresh: () => provider.loadExam(_examId, force: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                _ExamSummary(exam: widget.exam, results: results),
                if (processing > 0) ...[
                  const SizedBox(height: 12),
                  StatusBadge(
                    label:
                        '$processing more ${processing == 1 ? 'sheet' : 'sheets'} '
                        'being graded...',
                    icon: Icons.sync,
                    color: AppColors.info,
                  ),
                ],
                const SizedBox(height: 20),
                if (results.isEmpty)
                  const EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'No students graded yet',
                    message: 'Scanned sheets for this exam will show here.',
                  )
                else ...[
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search roll or registration',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionHeader(
                    title: 'Ranking',
                    action: Text(
                      '${visible.length} students',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ),
                  for (final r in visible) ...[
                    ResultRowTile(
                      result: r,
                      exam: widget.exam,
                      // Server sorts by percentage, so list order is rank.
                      rank: results.indexOf(r) + 1,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ExamSummary extends StatelessWidget {
  const _ExamSummary({required this.exam, required this.results});

  final Map<String, dynamic> exam;
  final List<Map<String, dynamic>> results;

  @override
  Widget build(BuildContext context) {
    final count = results.length;
    final pcts = results.map((r) => asDouble(r['percentage'])).toList();
    final avg = count == 0 ? 0.0 : pcts.reduce((a, b) => a + b) / count;
    final best = count == 0 ? 0.0 : pcts.reduce((a, b) => a > b ? a : b);
    final passed = results.where((r) => r['passed'] == true).length;

    Widget stat(String value, String label) => Expanded(
      child: Column(
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
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    return HeroPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exam['title']?.toString() ?? 'Exam',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${exam['subject'] ?? ''} • ${exam['total_questions'] ?? 0} questions',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              stat('$count', 'graded'),
              stat('${avg.round()}%', 'average'),
              stat('${best.round()}%', 'highest'),
              stat(
                count == 0 ? '0%' : '${(passed * 100 / count).round()}%',
                'passed',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
