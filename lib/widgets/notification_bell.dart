import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/notification_provider.dart';
import '../routes/app_routes.dart';
import '../themes/app_colors.dart';

/// Bell icon with the unread count; opens the notification centre.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationProvider>().unread;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.pushNamed(context, AppRoutes.notifications),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        backgroundColor: AppColors.error,
        child: Icon(
          unread > 0
              ? Icons.notifications_rounded
              : Icons.notifications_none_rounded,
          color: onDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }
}
