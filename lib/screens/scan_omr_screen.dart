import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/batch_scan_provider.dart';
import '../providers/results_provider.dart';
import '../routes/app_routes.dart';
import '../services/grading_service.dart';
import '../themes/app_colors.dart';
import '../themes/app_text_styles.dart';
import '../utils/scan_errors.dart';
import '../widgets/app_widgets.dart';
import 'camera_scan_screen.dart';

/// Scan entry point for an exam: single scan (camera or gallery) or batch camera mode, plus the batch queue.
class ScanOmrScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const ScanOmrScreen({super.key, required this.exam});

  @override
  State<ScanOmrScreen> createState() => _ScanOmrScreenState();
}

class _ScanOmrScreenState extends State<ScanOmrScreen> {
  final GradingService _grading = GradingService();

  File? selectedImage;

  /// Current step of a single-sheet grade, null when idle.
  GradeStage? _stage;

  /// Friendly explanation shown (with a Retake button) when a scan fails.
  String? scanFailure;

  bool get _busy => _stage != null;
  String get _examId => widget.exam['id'].toString();

  // --------------------------------------------------
  // SINGLE SHEET
  // --------------------------------------------------

  Future<void> _pickFromGallery() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() {
        selectedImage = File(file.path);
        scanFailure = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to acquire image: $e')));
    }
  }

  /// Opens the live scanner. A captured sheet is graded immediately.
  Future<void> _openCamera() async {
    final File? shot = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => CameraScanScreen(exam: widget.exam),
        fullscreenDialog: true,
      ),
    );
    if (shot == null || !mounted) return;
    setState(() {
      selectedImage = shot;
      scanFailure = null;
    });
    await _gradeSelected();
  }

  Future<void> _gradeSelected() async {
    final image = selectedImage;
    if (image == null || _busy) return;

    setState(() {
      _stage = GradeStage.reading;
      scanFailure = null;
    });

    try {
      final graded = await _grading.grade(
        examId: _examId,
        image: image,
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (!mounted) return;
      context.read<ResultsProvider>().invalidate(_examId);
      setState(() {
        _stage = null;
        selectedImage = null;
      });
      Navigator.pushNamed(
        context,
        AppRoutes.result,
        arguments: {'resultId': graded.resultId, 'exam': widget.exam},
      );
    } catch (e) {
      debugPrint('SCAN ERROR: $e');
      if (!mounted) return;
      setState(() {
        _stage = null;
        scanFailure = friendlyScanError(e);
      });
    }
  }

  // --------------------------------------------------
  // BATCH
  // --------------------------------------------------

  Future<void> _openBatchScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraScanScreen(batchExam: widget.exam),
        fullscreenDialog: true,
      ),
    );
  }

  // --------------------------------------------------
  // BUILD
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final jobs = context.watch<BatchScanProvider>().jobsFor(_examId);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan sheets')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _ExamHeader(exam: widget.exam),
          const SizedBox(height: 20),
          _ModeCard(
            icon: Icons.burst_mode_outlined,
            title: 'Batch scan',
            description:
                'Scan a whole class in one go. Sheets are captured '
                'continuously and graded in the background.',
            highlighted: true,
            badge: 'Fastest',
            onTap: _busy ? null : _openBatchScanner,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ModeCard(
                  icon: Icons.document_scanner_outlined,
                  title: 'Single sheet',
                  description: 'Scan one and see its result',
                  compact: true,
                  onTap: _busy ? null : _openCamera,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeCard(
                  icon: Icons.photo_library_outlined,
                  title: 'From gallery',
                  description: 'Grade a saved photo',
                  compact: true,
                  onTap: _busy ? null : _pickFromGallery,
                ),
              ),
            ],
          ),
          if (selectedImage != null) ...[
            const SizedBox(height: 20),
            _buildSelectedSheet(),
          ],
          if (scanFailure != null) ...[
            const SizedBox(height: 16),
            _buildFailureCard(),
          ],
          if (jobs.isNotEmpty) ...[
            const SizedBox(height: 28),
            _BatchQueue(exam: widget.exam, jobs: jobs),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedSheet() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 240,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(selectedImage!, fit: BoxFit.cover),
                if (_busy)
                  Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 14),
                        Text(
                          _stage == GradeStage.reading
                              ? 'Reading answers...'
                              : 'Calculating score...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            selectedImage = null;
                            scanFailure = null;
                          }),
                    child: const Text('Remove'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _gradeSelected,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Grade sheet'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: AppColors.error),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Couldn't read this sheet",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(scanFailure!, style: AppTextStyles.body),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _openCamera,
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Retake with camera'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Pieces
// ============================================================================

class _ExamHeader extends StatelessWidget {
  const _ExamHeader({required this.exam});

  final Map<String, dynamic> exam;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const IconBadge(icon: Icons.description_outlined, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exam['title']?.toString() ?? 'Exam',
                style: AppTextStyles.title,
              ),
              const SizedBox(height: 2),
              Text(
                '${exam['subject'] ?? 'No subject'} • '
                '${exam['total_questions'] ?? 0} questions',
                style: AppTextStyles.bodySecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.highlighted = false,
    this.compact = false,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool compact;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final fg = highlighted ? Colors.white : AppColors.textPrimary;
    final sub = highlighted
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textSecondary;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: highlighted
                    ? Colors.white.withValues(alpha: 0.18)
                    : AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: highlighted ? Colors.white : AppColors.primary,
              ),
            ),
            const Spacer(),
            if (badge != null)
              StatusBadge(
                label: badge!,
                color: AppColors.primary,
                background: Colors.white,
              ),
          ],
        ),
        SizedBox(height: compact ? 12 : 16),
        Text(
          title,
          style: TextStyle(
            color: fg,
            fontSize: compact ? 15 : 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(description, style: TextStyle(color: sub, fontSize: 13)),
      ],
    );

    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: highlighted ? AppColors.heroGradient : null,
              color: highlighted ? null : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: highlighted ? null : Border.all(color: AppColors.border),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Background batch progress for this exam, with per-sheet status.
class _BatchQueue extends StatelessWidget {
  const _BatchQueue({required this.exam, required this.jobs});

  final Map<String, dynamic> exam;
  final List<BatchJob> jobs;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<BatchScanProvider>();
    final examId = exam['id'].toString();
    final active = jobs.where((j) => j.isActive).length;
    final done = jobs.where((j) => j.status == BatchJobStatus.done).length;
    final failed = jobs.where((j) => j.status == BatchJobStatus.failed).length;
    final progress = jobs.isEmpty ? 0.0 : (done + failed) / jobs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Batch queue',
          action: done > 0
              ? TextButton(
                  onPressed: () => provider.clearFinished(examId),
                  child: const Text('Clear saved'),
                )
              : null,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        active > 0
                            ? 'Grading in the background...'
                            : 'All sheets processed',
                        style: AppTextStyles.subtitle,
                      ),
                    ),
                    Text(
                      '${done + failed}/${jobs.length}',
                      style: AppTextStyles.subtitle,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusBadge(
                      label: '$done saved',
                      icon: Icons.check_circle,
                      color: AppColors.success,
                    ),
                    if (active > 0)
                      StatusBadge(
                        label: '$active in progress',
                        icon: Icons.sync,
                        color: AppColors.info,
                      ),
                    if (failed > 0)
                      StatusBadge(
                        label: '$failed failed',
                        icon: Icons.error,
                        color: AppColors.error,
                      ),
                  ],
                ),
                if (failed > 0) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => provider.retryAllFailed(examId),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry failed sheets'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final job in jobs) ...[
          _JobTile(job: job, exam: exam),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.exam});

  final BatchJob job;
  final Map<String, dynamic> exam;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<BatchScanProvider>();

    Widget leading;
    String title;
    Widget subtitle;
    Widget? trailing;
    VoidCallback? onTap;

    switch (job.status) {
      case BatchJobStatus.queued:
      case BatchJobStatus.reading:
      case BatchJobStatus.scoring:
        leading = const SizedBox(
          width: 44,
          height: 44,
          child: Padding(
            padding: EdgeInsets.all(11),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
        title = 'Sheet';
        subtitle = Text(
          job.status == BatchJobStatus.queued
              ? 'Waiting...'
              : job.status == BatchJobStatus.reading
              ? 'Reading answers...'
              : 'Calculating score...',
          style: AppTextStyles.bodySecondary,
        );
      case BatchJobStatus.done:
        final pct = asDouble(job.result?['percentage']);
        final passed = job.result?['passed'] == true;
        leading = ScoreRing(
          fraction: pct / 100,
          color: scoreColor(pct, passed: passed),
          size: 44,
          stroke: 4,
          child: Text(
            '${pct.round()}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        );
        title = 'Roll ${job.roll}';
        subtitle = Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${formatNumber(asDouble(job.result?['marks']))}/'
              '${formatNumber(asDouble(job.result?['max_marks']))} • '
              'Grade ${job.result?['grade'] ?? '-'}',
              style: AppTextStyles.bodySecondary,
            ),
            if (job.duplicateRoll)
              const StatusBadge(
                label: 'Duplicate roll',
                color: AppColors.warning,
              ),
          ],
        );
        trailing = const Icon(
          Icons.chevron_right,
          color: AppColors.textSecondary,
        );
        onTap = () => Navigator.pushNamed(
          context,
          AppRoutes.result,
          arguments: {'resultId': job.resultId, 'exam': exam},
        );
      case BatchJobStatus.failed:
        leading = const IconBadge(
          icon: Icons.error_outline,
          color: AppColors.error,
        );
        title = 'Could not grade sheet';
        subtitle = Text(
          job.error ?? 'Unknown error',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodySecondary,
        );
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Retry',
              onPressed: () => provider.retry(job),
              icon: const Icon(Icons.refresh, color: AppColors.primary),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: () => provider.remove(job),
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
            ),
          ],
        );
        onTap = () => _showError(context);
    }

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        leading: leading,
        title: Text(title, style: AppTextStyles.subtitle),
        subtitle: subtitle,
        trailing: trailing,
      ),
    );
  }

  void _showError(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  job.image,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 14),
              Text("Couldn't read this sheet", style: AppTextStyles.title),
              const SizedBox(height: 6),
              Text(job.error ?? '', style: AppTextStyles.body),
            ],
          ),
        ),
      ),
    );
  }
}
