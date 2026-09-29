import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../services/class_service.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/charts.dart';

/// Class analytics for the teacher: headline numbers, exam averages over
/// time, pass rates, grade spread, daily attendance, leaderboard and the
/// students who need attention.
class ClassInsightsTab extends StatefulWidget {
  const ClassInsightsTab({super.key, required this.classId});

  final String classId;

  @override
  State<ClassInsightsTab> createState() => _ClassInsightsTabState();
}

class _ClassInsightsTabState extends State<ClassInsightsTab> {
  late Future<Map<String, dynamic>> _future = const ClassService().analytics(
    widget.classId,
  );

  void _reload() =>
      setState(() => _future = const ClassService().analytics(widget.classId));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
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
        final data = snapshot.data!;
        final summary = Map<String, dynamic>.from(data['summary'] as Map);
        final exams =
            [
                  for (final e in data['exams'] as List)
                    Map<String, dynamic>.from(e as Map),
                ]
                .where((e) => e['students'] != null && asInt(e['students']) > 0)
                .toList();
        final attendance = [
          for (final a in data['attendance'] as List)
            Map<String, dynamic>.from(a as Map),
        ];
        final grades = [
          for (final g in data['grade_distribution'] as List)
            Map<String, dynamic>.from(g as Map),
        ];
        final leaderboard = [
          for (final s in data['leaderboard'] as List)
            Map<String, dynamic>.from(s as Map),
        ];
        final atRisk = [
          for (final s in data['at_risk'] as List)
            Map<String, dynamic>.from(s as Map),
        ];

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.percent_rounded,
                      label: 'Class average',
                      value: summary['average'] == null
                          ? '—'
                          : '${formatNumber(asDouble(summary['average']))}%',
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      icon: Icons.event_available_outlined,
                      label: 'Attendance',
                      value: summary['attendance_rate'] == null
                          ? '—'
                          : '${formatNumber(asDouble(summary['attendance_rate']))}%',
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      icon: Icons.assignment_outlined,
                      label: 'Exams',
                      value: '${asInt(summary['exams'])}',
                      color: AppColors.chart[1],
                    ),
                  ),
                ],
              ),
              if (asInt(summary['unmatched_results']) > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${asInt(summary['unmatched_results'])} scanned results have a roll number '
                          'that is not on this roster, so they are not in these charts.',
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ChartCard(
                title: 'Exam averages',
                subtitle: 'Average and highest score per exam',
                legend: const Wrap(
                  spacing: 16,
                  children: [
                    LegendDot(color: AppColors.primary, label: 'Average'),
                    LegendDot(color: Color(0xFFF59E0B), label: 'Highest'),
                  ],
                ),
                child: PercentLineChart(
                  labels: [
                    for (final e in exams) _short(e['title'].toString()),
                  ],
                  series: [
                    [
                      for (final e in exams)
                        e['average'] == null ? null : asDouble(e['average']),
                    ],
                    [
                      for (final e in exams)
                        e['highest'] == null ? null : asDouble(e['highest']),
                    ],
                  ],
                  colors: [AppColors.primary, AppColors.chart[2]],
                  dashed: const {1},
                ),
              ),
              const SizedBox(height: 12),
              ChartCard(
                title: 'Pass rate',
                subtitle: 'Share of students who passed each exam',
                child: SimpleBarChart(
                  labels: [
                    for (final e in exams) _short(e['title'].toString()),
                  ],
                  values: [for (final e in exams) asDouble(e['pass_rate'])],
                  colors: [
                    for (final e in exams)
                      asDouble(e['pass_rate']) >= 60
                          ? AppColors.success
                          : AppColors.warning,
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ChartCard(
                title: 'Grade distribution',
                subtitle: 'All graded sheets in this class',
                height: 170,
                child: SimpleBarChart(
                  labels: [for (final g in grades) g['grade'].toString()],
                  values: [for (final g in grades) asDouble(g['count'])],
                  percent: false,
                  colors: AppColors.chart,
                ),
              ),
              const SizedBox(height: 12),
              ChartCard(
                title: 'Daily attendance',
                subtitle: 'Present or late, per day',
                child: PercentLineChart(
                  labels: [for (final a in attendance) shortDate(a['date'])],
                  series: [
                    [
                      for (final a in attendance)
                        a['rate'] == null ? null : asDouble(a['rate']),
                    ],
                  ],
                  colors: const [AppColors.success],
                ),
              ),
              const SizedBox(height: 20),
              if (atRisk.isNotEmpty) ...[
                SectionHeader(title: 'Needs attention (${atRisk.length})'),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Average under 40% or attendance under 75%.',
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
                for (final s in atRisk)
                  _StudentRow(student: s, color: AppColors.error),
                const SizedBox(height: 16),
              ],
              const SectionHeader(title: 'Leaderboard'),
              if (leaderboard.isEmpty)
                const EmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: 'No ranking yet',
                  message:
                      'Rankings appear once sheets for this class are graded.',
                )
              else
                for (final s in leaderboard)
                  _StudentRow(student: s, rank: asInt(s['rank'])),
            ],
          ),
        );
      },
    );
  }

  static String _short(String title) =>
      title.length <= 8 ? title : '${title.substring(0, 7)}…';
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student, this.rank, this.color});

  final Map<String, dynamic> student;
  final int? rank;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final avg = student['average'];
    final att = student['attendance_rate'];
    final medal = switch (rank) {
      1 => const Color(0xFFF59E0B),
      2 => const Color(0xFF94A3B8),
      3 => const Color(0xFFB45309),
      _ => AppColors.neutralSoft,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: rank != null
            ? CircleAvatar(
                backgroundColor: medal.withValues(alpha: rank! <= 3 ? 0.2 : 1),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: rank! <= 3 ? medal : AppColors.textPrimary,
                  ),
                ),
              )
            : Icon(Icons.warning_amber_rounded, color: color),
        title: Text(student['name'].toString(), style: AppTextStyles.subtitle),
        subtitle: Text(
          [
            'Roll ${student['roll_number']}',
            if (att != null) 'Attendance ${formatNumber(asDouble(att))}%',
            '${asInt(student['exams_taken'])} exams',
          ].join(' • '),
        ),
        trailing: Text(
          avg == null ? '—' : '${formatNumber(asDouble(avg))}%',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: avg == null
                ? AppColors.textSecondary
                : scoreColor(asDouble(avg)),
          ),
        ),
        onTap: () {
          final classId = context
              .findAncestorWidgetOfExactType<ClassInsightsTab>()
              ?.classId;
          Navigator.pushNamed(
            context,
            AppRoutes.studentReport,
            arguments: {
              'class': {'id': classId},
              'student': student,
            },
          );
        },
      ),
    );
  }
}
