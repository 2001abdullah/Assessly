import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/class_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/student_provider.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/app_widgets.dart';

/// Notification centre: results published, announcements, attendance,
/// join requests and approvals, newest first.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

({IconData icon, Color color}) _style(String type) => switch (type) {
  'results_published' => (
    icon: Icons.fact_check_outlined,
    color: AppColors.primary,
  ),
  'announcement' => (icon: Icons.campaign_outlined, color: AppColors.warning),
  'attendance_absent' => (
    icon: Icons.event_busy_outlined,
    color: AppColors.error,
  ),
  'join_request' => (
    icon: Icons.person_add_alt_1_outlined,
    color: AppColors.info,
  ),
  'enrolment_approved' => (
    icon: Icons.how_to_reg_outlined,
    color: AppColors.success,
  ),
  _ => (icon: Icons.notifications_none_rounded, color: AppColors.neutral),
};

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().refresh();
      // Whatever the notifications are about is probably new data.
      if (context.read<AuthProvider>().isStudent) {
        context.read<StudentProvider>().refresh();
      } else {
        context.read<ClassProvider>().refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final items = provider.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (provider.unread > 0)
            TextButton(
              onPressed: provider.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: items.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (provider.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    const EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'You are all caught up',
                      message: 'Results, announcements and class updates will appear here.',
                    ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) {
                  final n = items[i];
                  final unread = n['read_at'] == null;
                  final style = _style(n['type'].toString());
                  final body = n['body']?.toString() ?? '';
                  return ListTile(
                    onTap: () => provider.markRead(n['id'].toString()),
                    tileColor: unread
                        ? AppColors.primarySoft.withValues(alpha: 0.5)
                        : null,
                    shape: const RoundedRectangleBorder(),
                    leading: IconBadge(
                      icon: style.icon,
                      color: style.color,
                      size: 42,
                    ),
                    title: Text(
                      n['title'].toString(),
                      style: AppTextStyles.subtitle.copyWith(
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (body.isNotEmpty) body,
                        timeAgo(n['created_at']),
                      ].join('\n'),
                    ),
                    isThreeLine: body.isNotEmpty,
                    trailing: unread
                        ? const CircleAvatar(
                            radius: 4,
                            backgroundColor: AppColors.primary,
                          )
                        : null,
                  );
                },
              ),
      ),
    );
  }
}
