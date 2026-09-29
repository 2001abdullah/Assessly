import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../themes/app_colors.dart';
import '../themes/app_text_styles.dart';
import 'app_widgets.dart';

/// Exam summary card used on the home screen and the exam list.
class ExamCard extends StatelessWidget {
  const ExamCard({
    super.key,
    required this.exam,
    this.gradedCount,
    this.onDelete,
  });

  final Map<String, dynamic> exam;
  final int? gradedCount;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final title = exam['title']?.toString() ?? 'Untitled exam';
    final subject = exam['subject']?.toString() ?? 'No subject';
    final questions = exam['total_questions']?.toString() ?? '0';
    final className = exam['class_name']?.toString();
    final published = exam['results_published_at'] != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.examDetails,
          arguments: exam,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            children: [
              IconBadge(
                icon: Icons.description_outlined,
                color: AppColors.primary,
                size: 48,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.subtitle,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [?className, subject, '$questions questions'].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySecondary,
                    ),
                    if ((gradedCount ?? 0) > 0 || published) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if ((gradedCount ?? 0) > 0)
                            StatusBadge(
                              label: '$gradedCount graded',
                              icon: Icons.check_circle_outline,
                              color: AppColors.success,
                            ),
                          if (published)
                            const StatusBadge(
                              label: 'Published',
                              icon: Icons.visibility_outlined,
                              color: AppColors.info,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Delete exam',
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
