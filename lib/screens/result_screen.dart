import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/results_provider.dart';
import '../themes/app_colors.dart';
import '../themes/app_text_styles.dart';
import '../widgets/app_widgets.dart';

/// Full result for one student: score summary plus every question with the
/// student's answer, the correct answer and whether it was right or wrong.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.resultId, this.exam});

  final String resultId;

  /// Optional; the details endpoint also returns the exam.
  final Map<String, dynamic>? exam;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

enum _Filter { all, correct, wrong, blank, review }

class _ResultScreenState extends State<ResultScreen> {
  late Future<Map<String, dynamic>> _future;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _future = context.read<ResultsProvider>().details(widget.resultId);
  }

  void _reload() {
    setState(() {
      _future = context.read<ResultsProvider>().details(
        widget.resultId,
        force: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          return _buildResult(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildResult(Map<String, dynamic> data) {
    final exam = data['exam'] is Map
        ? Map<String, dynamic>.from(data['exam'])
        : (widget.exam ?? const {});
    final student = data['student'] is Map ? data['student'] as Map : const {};
    final summary = data['summary'] is Map ? data['summary'] as Map : const {};
    final questions = [
      for (final q in (data['questions'] as List? ?? const []))
        if (q is Map) Map<String, dynamic>.from(q),
    ];

    final counts = {
      _Filter.all: questions.length,
      _Filter.correct: _count(questions, 'correct'),
      _Filter.wrong: _count(questions, 'wrong'),
      _Filter.blank: _count(questions, 'blank'),
      _Filter.review: _count(questions, 'ambiguous'),
    };
    final visible = questions.where(_matches).toList();

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverList.list(
              children: [
                _SummaryHero(
                  examTitle: exam['title']?.toString() ?? 'Exam',
                  subject: exam['subject']?.toString(),
                  summary: summary,
                  roll: formatIdentifier(student['roll_number']),
                  registration: formatIdentifier(
                    student['registration_number'],
                  ),
                ),
                const SizedBox(height: 16),
                _StatsRow(summary: summary),
                const SizedBox(height: 16),
                _DistributionBar(summary: summary),
                const SizedBox(height: 24),
                if (questions.isNotEmpty) ...[
                  const SectionHeader(title: 'Answer map'),
                  _AnswerMap(questions: questions),
                  const SizedBox(height: 24),
                ],
                SectionHeader(
                  title: 'Question breakdown',
                  action: Text(
                    '${visible.length} shown',
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
                _buildFilters(counts),
                const SizedBox(height: 12),
              ],
            ),
          ),
          if (questions.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.key_off_outlined,
                  title: 'No answer key',
                  message:
                      'Add an answer key to this exam to see '
                      'question-by-question results.',
                ),
              ),
            )
          else if (visible.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: Text(
                    'No questions in this category.',
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _QuestionTile(question: visible[i]),
              ),
            ),
        ],
      ),
    );
  }

  int _count(List<Map<String, dynamic>> questions, String status) =>
      questions.where((q) => q['status'] == status).length;

  bool _matches(Map<String, dynamic> q) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.correct:
        return q['status'] == 'correct';
      case _Filter.wrong:
        return q['status'] == 'wrong';
      case _Filter.blank:
        return q['status'] == 'blank';
      case _Filter.review:
        return q['status'] == 'ambiguous';
    }
  }

  Widget _buildFilters(Map<_Filter, int> counts) {
    const labels = {
      _Filter.all: 'All',
      _Filter.correct: 'Correct',
      _Filter.wrong: 'Wrong',
      _Filter.blank: 'Blank',
      _Filter.review: 'Review',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${labels[f]}  ${counts[f]}'),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Question status styling
// ============================================================================

class _StatusStyle {
  const _StatusStyle(this.label, this.color, this.soft, this.icon);

  final String label;
  final Color color;
  final Color soft;
  final IconData icon;

  static _StatusStyle of(String? status) {
    switch (status) {
      case 'correct':
        return const _StatusStyle(
          'Correct',
          AppColors.success,
          AppColors.successSoft,
          Icons.check_rounded,
        );
      case 'wrong':
        return const _StatusStyle(
          'Wrong',
          AppColors.error,
          AppColors.errorSoft,
          Icons.close_rounded,
        );
      case 'blank':
        return const _StatusStyle(
          'Blank',
          AppColors.neutral,
          AppColors.neutralSoft,
          Icons.remove_rounded,
        );
      case 'ambiguous':
        return const _StatusStyle(
          'Needs review',
          AppColors.warning,
          AppColors.warningSoft,
          Icons.priority_high_rounded,
        );
      default:
        return const _StatusStyle(
          'No key',
          AppColors.neutral,
          AppColors.surfaceMuted,
          Icons.help_outline_rounded,
        );
    }
  }
}

// ============================================================================
// Sections
// ============================================================================

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({
    required this.examTitle,
    required this.subject,
    required this.summary,
    required this.roll,
    required this.registration,
  });

  final String examTitle;
  final String? subject;
  final Map summary;
  final String roll;
  final String registration;

  @override
  Widget build(BuildContext context) {
    final percentage = asDouble(summary['percentage']);
    final marks = asDouble(summary['marks']);
    final maxMarks = asDouble(summary['max_marks']);
    final passed = summary['passed'] == true;
    final grade = summary['grade']?.toString() ?? '-';
    final needsReview = summary['needs_review'] == true;

    return HeroPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            examTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subject != null && subject!.isNotEmpty)
            Text(
              subject!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              ScoreRing(
                fraction: percentage / 100,
                color: Colors.white,
                trackColor: Colors.white.withValues(alpha: 0.2),
                size: 116,
                stroke: 10,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${formatNumber(percentage)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Grade $grade',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
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
                    Text(
                      'Score',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatNumber(marks),
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: ' / ${formatNumber(maxMarks)}',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusBadge(
                          label: passed ? 'PASSED' : 'FAILED',
                          icon: passed ? Icons.verified : Icons.cancel,
                          color: passed
                              ? AppColors.success
                              : AppColors.error,
                          background: Colors.white,
                        ),
                        if (needsReview)
                          const StatusBadge(
                            label: 'Needs review',
                            icon: Icons.flag_outlined,
                            color: AppColors.warning,
                            background: Colors.white,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _idCell('Roll no.', roll),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                const SizedBox(width: 14),
                _idCell('Registration', registration),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _idCell(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.summary});

  final Map summary;

  @override
  Widget build(BuildContext context) {
    Widget tile(String key, String label, IconData icon, Color color) =>
        Expanded(
          child: StatTile(
            icon: icon,
            label: label,
            value: asInt(summary[key]).toString(),
            color: color,
          ),
        );
    return Row(
      children: [
        tile('correct', 'Correct', Icons.check_rounded, AppColors.success),
        const SizedBox(width: 8),
        tile('wrong', 'Wrong', Icons.close_rounded, AppColors.error),
        const SizedBox(width: 8),
        tile('blank', 'Blank', Icons.remove_rounded, AppColors.neutral),
        const SizedBox(width: 8),
        tile(
          'ambiguous',
          'Review',
          Icons.priority_high_rounded,
          AppColors.warning,
        ),
      ],
    );
  }
}

/// Stacked bar showing the share of correct / wrong / blank / review answers.
class _DistributionBar extends StatelessWidget {
  const _DistributionBar({required this.summary});

  final Map summary;

  @override
  Widget build(BuildContext context) {
    final parts = [
      (asInt(summary['correct']), AppColors.success),
      (asInt(summary['wrong']), AppColors.error),
      (asInt(summary['blank']), AppColors.neutralSoft),
      (asInt(summary['ambiguous']), AppColors.warning),
    ].where((p) => p.$1 > 0).toList();
    if (parts.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (final p in parts)
              Expanded(flex: p.$1, child: ColoredBox(color: p.$2)),
          ],
        ),
      ),
    );
  }
}

/// Grid of numbered squares, one per question, coloured by outcome.
class _AnswerMap extends StatelessWidget {
  const _AnswerMap({required this.questions});

  final List<Map<String, dynamic>> questions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final q in questions)
                Builder(
                  builder: (_) {
                    final style = _StatusStyle.of(q['status']?.toString());
                    return Tooltip(
                      message:
                          'Q${q['question_number']}: ${style.label}',
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: style.soft,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: style.color.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          '${q['question_number']}',
                          style: TextStyle(
                            color: style.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final s in ['correct', 'wrong', 'blank', 'ambiguous'])
                _legend(_StatusStyle.of(s)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(_StatusStyle style) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: style.color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(style.label, style: AppTextStyles.caption),
    ],
  );
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.question});

  final Map<String, dynamic> question;

  @override
  Widget build(BuildContext context) {
    final status = question['status']?.toString();
    final style = _StatusStyle.of(status);
    final given = question['given_answer']?.toString();
    final correct = question['correct_answer']?.toString();
    final marks = asDouble(question['marks']);
    final marksText = marks > 0
        ? '+${formatNumber(marks)}'
        : formatNumber(marks);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: style.soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Q${question['question_number']}',
              style: TextStyle(
                color: style.color,
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
                Row(
                  children: [
                    Icon(style.icon, size: 16, color: style.color),
                    const SizedBox(width: 4),
                    Text(
                      style.label,
                      style: TextStyle(
                        color: style.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _answerChip(
                      'Marked',
                      status == 'ambiguous' && (given == null || given.isEmpty)
                          ? '?'
                          : (given == null || given.isEmpty ? '—' : given),
                      status == 'correct'
                          ? AppColors.success
                          : status == 'wrong'
                          ? AppColors.error
                          : AppColors.neutral,
                    ),
                    if (status != 'correct')
                      _answerChip(
                        'Correct',
                        correct ?? '—',
                        AppColors.success,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            marksText,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: marks > 0
                  ? AppColors.success
                  : marks < 0
                  ? AppColors.error
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _answerChip(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: AppTextStyles.bodySecondary),
        Container(
          constraints: const BoxConstraints(minWidth: 26),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
