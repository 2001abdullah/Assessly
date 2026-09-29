import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/exam_provider.dart';
import '../themes/app_colors.dart';
import '../themes/app_text_styles.dart';
import 'app_widgets.dart';

/// Bottom sheet that lets the user choose one of their exams.
Future<Map<String, dynamic>?> pickExam(
  BuildContext context, {
  required String title,
}) {
  context.read<ExamProvider>().load();
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (context, controller) {
        final provider = context.watch<ExamProvider>();
        final exams = provider.exams;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(title, style: AppTextStyles.title),
            ),
            Expanded(
              child: provider.isLoading && exams.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : exams.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'You have no exams yet. Create one first.',
                        style: AppTextStyles.bodySecondary,
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: exams.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, i) {
                        final exam = exams[i];
                        return ListTile(
                          leading: const IconBadge(
                            icon: Icons.description_outlined,
                          ),
                          title: Text(
                            exam['title']?.toString() ?? 'Untitled exam',
                            style: AppTextStyles.subtitle,
                          ),
                          subtitle: Text(
                            '${exam['subject'] ?? 'No subject'} • '
                            '${exam['total_questions'] ?? 0} questions',
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppColors.textSecondary,
                          ),
                          onTap: () => Navigator.pop(sheetContext, exam),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
