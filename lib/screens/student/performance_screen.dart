import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/student_provider.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/charts.dart';

/// The student's progress: score trend against the class average, grade
/// spread, attendance breakdown and their rank in each class.
class PerformanceScreen extends StatelessWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final student = context.watch<StudentProvider>();
    final overview = student.overview;
    final s = student.summary;
    final trend = [
      for (final t in (overview?['trend'] as List? ?? const []))
        Map<String, dynamic>.from(t as Map),
    ];
    final grades = [
      for (final g in (overview?['grade_distribution'] as List? ?? const []))
        Map<String, dynamic>.from(g as Map),
    ];
    final ranks = [
      for (final r in (overview?['class_ranks'] as List? ?? const []))
        Map<String, dynamic>.from(r as Map),
    ];
    final att = Map<String, dynamic>.from(s['attendance'] as Map? ?? const {});

    // Improvement: last result vs the average of the ones before it.
    double? change;
    if (trend.length >= 2) {
      final last = asDouble(trend.last['percentage']);
      final before = trend
          .sublist(0, trend.length - 1)
          .map((t) => asDouble(t['percentage']));
      change = last - before.reduce((a, b) => a + b) / (trend.length - 1);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My progress')),
      body: RefreshIndicator(
        onRefresh: student.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (student.isLoading && !student.hasLoaded)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (student.error != null && !student.hasLoaded)
              ErrorState(message: student.error!, onRetry: student.refresh)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.percent_rounded,
                      label: 'Average',
                      value: s['average'] == null
                          ? '—'
                          : '${formatNumber(asDouble(s['average']))}%',
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      icon: Icons.star_outline_rounded,
                      label: 'Best',
                      value: s['best'] == null
                          ? '—'
                          : '${formatNumber(asDouble(s['best']))}%',
                      color: AppColors.chart[2],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      icon: Icons.verified_outlined,
                      label: 'Passed',
                      value: '${asInt(s['passed'])}/${asInt(s['exams_taken'])}',
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
              if (change != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: change >= 0
                        ? AppColors.successSoft
                        : AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        change >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: change >= 0
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          change >= 0
                              ? 'Your latest result is ${formatNumber(change)} points above your earlier average. Keep it up!'
                              : 'Your latest result is ${formatNumber(-change)} points below your earlier average.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: change >= 0
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ChartCard(
                title: 'Score trend',
                subtitle: 'Your percentage in each exam vs the class average',
                legend: const Wrap(
                  spacing: 16,
                  children: [
                    LegendDot(color: AppColors.primary, label: 'You'),
                    LegendDot(color: AppColors.neutral, label: 'Class average'),
                  ],
                ),
                child: PercentLineChart(
                  labels: [for (final t in trend) shortDate(t['date'])],
                  series: [
                    [for (final t in trend) asDouble(t['percentage'])],
                    [for (final t in trend) asDouble(t['class_average'])],
                  ],
                  colors: const [AppColors.primary, AppColors.neutral],
                  dashed: const {1},
                ),
              ),
              const SizedBox(height: 12),
              ChartCard(
                title: 'Grades',
                subtitle: 'How often you got each grade',
                height: 160,
                child: SimpleBarChart(
                  labels: [for (final g in grades) g['grade'].toString()],
                  values: [for (final g in grades) asDouble(g['count'])],
                  percent: false,
                  colors: AppColors.chart,
                ),
              ),
              const SizedBox(height: 12),
              ChartCard(
                title: 'Attendance',
                subtitle: 'All your classes',
                height: 150,
                child: Row(
                  children: [
                    Expanded(
                      child: DonutChart(
                        values: [
                          asDouble(att['present']),
                          asDouble(att['late']),
                          asDouble(att['absent']),
                          asDouble(att['excused']),
                        ],
                        colors: const [
                          AppColors.success,
                          AppColors.warning,
                          AppColors.error,
                          AppColors.info,
                        ],
                        center: Text(
                          s['attendance_rate'] == null
                              ? '—'
                              : '${formatNumber(asDouble(s['attendance_rate']))}%',
                          style: AppTextStyles.title,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LegendDot(
                          color: AppColors.success,
                          label: 'Present ${asInt(att['present'])}',
                        ),
                        const SizedBox(height: 6),
                        LegendDot(
                          color: AppColors.warning,
                          label: 'Late ${asInt(att['late'])}',
                        ),
                        const SizedBox(height: 6),
                        LegendDot(
                          color: AppColors.error,
                          label: 'Absent ${asInt(att['absent'])}',
                        ),
                        const SizedBox(height: 6),
                        LegendDot(
                          color: AppColors.info,
                          label: 'Excused ${asInt(att['excused'])}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (ranks.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeader(title: 'Class standing'),
                for (final r in ranks)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const IconBadge(
                        icon: Icons.emoji_events_outlined,
                        color: Color(0xFFF59E0B),
                        size: 42,
                      ),
                      title: Text(
                        r['class_name'].toString(),
                        style: AppTextStyles.subtitle,
                      ),
                      subtitle: Text(
                        [
                          if (r['average'] != null)
                            'Average ${formatNumber(asDouble(r['average']))}%',
                          if (r['attendance_rate'] != null)
                            'Attendance ${formatNumber(asDouble(r['attendance_rate']))}%',
                        ].join(' • '),
                      ),
                      trailing: Text(
                        r['rank'] == null
                            ? '—'
                            : '#${asInt(r['rank'])}/${asInt(r['out_of'])}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
