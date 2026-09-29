import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../services/class_service.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/charts.dart';
import 'attendance_screen.dart' show attendanceColor, attendanceLabel;

/// Teacher's view of one student in a class: score trend against the class
/// average, every result, and their attendance record.
class StudentReportScreen extends StatefulWidget {
  const StudentReportScreen({
    super.key,
    required this.classId,
    required this.student,
  });

  final String classId;
  final Map<String, dynamic> student;

  @override
  State<StudentReportScreen> createState() => _StudentReportScreenState();
}

class _StudentReportScreenState extends State<StudentReportScreen> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() => const ClassService().studentReport(
    widget.classId,
    widget.student['id'].toString(),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.student['name'].toString())),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final data = snapshot.data!;
          final student = Map<String, dynamic>.from(data['student'] as Map);
          final results = [
            for (final r in data['results'] as List)
              Map<String, dynamic>.from(r as Map),
          ];
          final att = Map<String, dynamic>.from(data['attendance'] as Map);
          final records = [
            for (final r in (att['records'] as List? ?? const []))
              Map<String, dynamic>.from(r as Map),
          ];
          final avg = results.isEmpty
              ? null
              : results
                        .map((r) => asDouble(r['percentage']))
                        .reduce((a, b) => a + b) /
                    results.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student['name'].toString(),
                        style: AppTextStyles.title,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          'Roll ${student['roll_number']}',
                          if (student['username'] != null)
                            'Login ${student['username']}',
                          if (student['email'] != null) student['email'],
                          if (student['has_account'] != true) 'No app account',
                        ].join(' • '),
                        style: AppTextStyles.bodySecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.percent_rounded,
                      label: 'Average',
                      value: avg == null ? '—' : '${formatNumber(avg)}%',
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      icon: Icons.event_available_outlined,
                      label: 'Attendance',
                      value: att['rate'] == null
                          ? '—'
                          : '${formatNumber(asDouble(att['rate']))}%',
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      icon: Icons.assignment_turned_in_outlined,
                      label: 'Exams',
                      value: '${results.length}',
                      color: AppColors.chart[1],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ChartCard(
                title: 'Score trend',
                subtitle: 'This student vs the class average',
                legend: const Wrap(
                  spacing: 16,
                  children: [
                    LegendDot(color: AppColors.primary, label: 'Student'),
                    LegendDot(color: AppColors.neutral, label: 'Class average'),
                  ],
                ),
                child: PercentLineChart(
                  labels: [for (final r in results) shortDate(r['date'])],
                  series: [
                    [for (final r in results) asDouble(r['percentage'])],
                    [for (final r in results) asDouble(r['class_average'])],
                  ],
                  colors: const [AppColors.primary, AppColors.neutral],
                  dashed: const {1},
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Results'),
              if (results.isEmpty)
                const EmptyState(
                  icon: Icons.assignment_outlined,
                  title: 'No results yet',
                  message: 'Results appear when a sheet with this roll number is graded.',
                )
              else
                for (final r in results.reversed)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.result,
                        arguments: {'resultId': r['result_id']},
                      ),
                      title: Text(
                        r['exam_title'].toString(),
                        style: AppTextStyles.subtitle,
                      ),
                      subtitle: Text(
                        'Rank ${asInt(r['rank'])} of ${asInt(r['out_of'])} • class avg ${formatNumber(asDouble(r['class_average']))}%',
                      ),
                      trailing: Text(
                        '${formatNumber(asDouble(r['percentage']))}%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: scoreColor(
                            asDouble(r['percentage']),
                            passed: r['passed'] as bool?,
                          ),
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Attendance'),
              if (records.isEmpty)
                const EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'No attendance recorded',
                  message:
                      'Days you take attendance for this class appear here.',
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in records.take(60))
                      Tooltip(
                        message:
                            '${r['session_date']}: ${attendanceLabel(r['status'].toString())}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: attendanceColor(r['status'].toString())
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            shortDate(r['session_date']),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: attendanceColor(r['status'].toString()),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
