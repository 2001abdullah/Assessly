import 'package:assessly/providers/exam_provider.dart';
import 'package:assessly/providers/results_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/services/exam_service.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:assessly/widgets/app_widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ExamDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> exam;
  const ExamDetailsScreen({super.key, required this.exam});

  @override
  State<ExamDetailsScreen> createState() => _ExamDetailsScreenState();
}

class _ExamDetailsScreenState extends State<ExamDetailsScreen> {
  bool _generating = false;

  Map<String, dynamic> get exam => widget.exam;
  String get _examId => exam['id'].toString();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ResultsProvider>().loadExam(_examId),
    );
  }

  Future<void> _generateSheet() async {
    setState(() => _generating = true);
    try {
      final bytes = await ExamService().downloadOmrSheet(_examId);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save OMR sheet',
        fileName: '${exam['title']}-omr.pdf',
        bytes: bytes,
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: AppColors.error),
        title: const Text('Delete exam?'),
        content: Text(
          '"${exam['title']}" and all of its answer keys and results will be '
          'permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final results = context.read<ResultsProvider>();
    try {
      await context.read<ExamProvider>().delete(_examId);
      results.removeExam(_examId);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('"${exam['title']}" deleted.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete exam: $error')),
      );
    }
  }

  void _open(String route) =>
      Navigator.pushNamed(context, route, arguments: exam);

  @override
  Widget build(BuildContext context) {
    final results = context.watch<ResultsProvider>().resultsFor(_examId);
    final count = results?.length ?? 0;
    final avg = count == 0
        ? 0.0
        : results!.map((r) => asDouble(r['percentage'])).reduce((a, b) => a + b) /
              count;
    final passed = results?.where((r) => r['passed'] == true).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text('Delete exam'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam['title']?.toString() ?? 'Exam',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${exam['subject'] ?? 'No subject'} • '
                  '${exam['total_questions'] ?? 0} questions',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _stat('$count', 'Graded'),
                    _stat(count == 0 ? '—' : '${avg.round()}%', 'Average'),
                    _stat(
                      count == 0 ? '—' : '${(passed * 100 / count).round()}%',
                      'Passed',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _PrimaryAction(
            icon: Icons.document_scanner_outlined,
            title: 'Scan answer sheets',
            subtitle: 'Single sheet or continuous batch scanning',
            onTap: () => _open(AppRoutes.scanOmr),
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Set up'),
          _ActionTile(
            icon: Icons.key_outlined,
            color: AppColors.warning,
            title: 'Answer key',
            subtitle: 'Correct option for every question',
            onTap: () => _open(AppRoutes.answerKey),
          ),
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.rule_outlined,
            color: AppColors.secondary,
            title: 'Scoring rules',
            subtitle: 'Marks, negative marking and pass mark',
            onTap: () => _open(AppRoutes.scoringRules),
          ),
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.picture_as_pdf_outlined,
            color: AppColors.error,
            title: 'OMR sheet',
            subtitle: 'Download a printable answer sheet',
            trailing: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : null,
            onTap: _generating ? null : _generateSheet,
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Results'),
          _ActionTile(
            icon: Icons.groups_outlined,
            color: AppColors.success,
            title: 'Student results',
            subtitle: count == 0
                ? 'No sheets graded yet'
                : '$count graded • ranking and per-question detail',
            onTap: () => _open(AppRoutes.studentResults),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
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
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.subtitle.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                    Text(subtitle, style: AppTextStyles.bodySecondary),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: IconBadge(icon: icon, color: color),
        title: Text(title, style: AppTextStyles.subtitle),
        subtitle: Text(subtitle, style: AppTextStyles.bodySecondary),
        trailing:
            trailing ??
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      ),
    );
  }
}
