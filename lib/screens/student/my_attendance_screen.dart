import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/student_provider.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';
import '../teacher/attendance_screen.dart'
    show attendanceColor, attendanceLabel;

/// The student's attendance in each class: rate, counts and every day.
class MyAttendanceScreen extends StatelessWidget {
  const MyAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final student = context.watch<StudentProvider>();
    final classes = student.attendance;

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
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
            else if (classes.isEmpty)
              const EmptyState(
                icon: Icons.event_available_outlined,
                title: 'No attendance yet',
                message: 'Once you are in a class, the days your teacher takes attendance show up here.',
              )
            else
              for (final c in classes) _ClassAttendance(data: c),
          ],
        ),
      ),
    );
  }
}

class _ClassAttendance extends StatelessWidget {
  const _ClassAttendance({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rate = data['rate'];
    final records = [
      for (final r in (data['records'] as List? ?? const []))
        Map<String, dynamic>.from(r as Map),
    ];
    final color = rate == null
        ? AppColors.neutral
        : asDouble(rate) >= 75
        ? AppColors.success
        : AppColors.warning;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ScoreRing(
                  fraction: rate == null ? 0 : asDouble(rate) / 100,
                  size: 58,
                  stroke: 7,
                  color: color,
                  child: Text(
                    rate == null ? '—' : '${asDouble(rate).round()}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['class_name'].toString(),
                        style: AppTextStyles.title,
                      ),
                      Text(
                        '${asInt(data['present'])} present • ${asInt(data['absent'])} absent'
                        '${asInt(data['late']) > 0 ? ' • ${asInt(data['late'])} late' : ''}',
                        style: AppTextStyles.bodySecondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (rate != null && asDouble(rate) < 75) ...[
              const SizedBox(height: 12),
              Text(
                'Your attendance is below 75%.',
                style: TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (records.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in records.take(60))
                    Tooltip(
                      message:
                          '${r['date']}: ${attendanceLabel(r['status'].toString())}',
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
                          shortDate(r['date']),
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
          ],
        ),
      ),
    );
  }
}
