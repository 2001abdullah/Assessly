import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/class_provider.dart';
import '../routes/app_routes.dart';
import '../themes/app_colors.dart';
import '../themes/app_text_styles.dart';
import 'app_widgets.dart';

/// Bottom sheet listing the teacher's classes. Returns the chosen class, or
/// null. With no classes it offers to create one.
Future<Map<String, dynamic>?> pickClass(
  BuildContext context, {
  String title = 'Choose a class',
}) async {
  final provider = context.read<ClassProvider>();
  await provider.load();
  if (!context.mounted) return null;
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final classes = provider.classes;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: AppTextStyles.title),
                const SizedBox(height: 12),
                if (classes.isEmpty)
                  EmptyState(
                    icon: Icons.groups_2_outlined,
                    title: 'No classes yet',
                    message: 'Create a class first.',
                    action: FilledButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.pushNamed(context, AppRoutes.createClass);
                      },
                      child: const Text('Create class'),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: classes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final c = classes[i];
                        return ListTile(
                          tileColor: AppColors.surfaceMuted,
                          leading: const IconBadge(
                            icon: Icons.groups_2_outlined,
                            size: 40,
                          ),
                          title: Text(
                            c['name'].toString(),
                            style: AppTextStyles.subtitle,
                          ),
                          subtitle: Text('${c['student_count'] ?? 0} students'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.pop(sheetContext, c),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
