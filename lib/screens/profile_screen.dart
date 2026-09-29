import 'dart:io';

import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/screens/student/student_home_screen.dart'
    show showJoinClassSheet;
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:assessly/widgets/app_widgets.dart';
import 'package:assessly/widgets/file_export.dart';
import 'package:assessly/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

/// Profile tab: picture, name and role, then grouped settings (account,
/// classes, app) and the sign-out / delete-account actions.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploading = false;

  Future<void> _changePhoto() async {
    final user = context.read<AuthProvider>().user;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheet, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheet, 'gallery'),
            ),
            if (user?.hasAvatar ?? false)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () => Navigator.pop(sheet, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final auth = context.read<AuthProvider>();
    setState(() => _uploading = true);
    try {
      if (choice == 'remove') {
        await auth.removeAvatar();
      } else {
        // Resized on the phone: a 512 px JPEG is a few dozen KB.
        final picked = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          preferredCameraDevice: CameraDevice.front,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85,
        );
        if (picked != null) await auth.setAvatar(File(picked.path));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.roleSelect,
      (route) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final student = context.read<AuthProvider>().isStudent;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account permanently?'),
        content: Text(
          student
              ? 'This deletes your account and removes you from pending class requests. '
                    'Your teachers keep their class records. This cannot be undone.'
              : 'This deletes your account, classes, exams, answer keys, scans, attendance and results. '
                    'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AuthProvider>().deleteAccount();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.roleSelect,
        (route) => false,
      );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => context.read<AuthProvider>().loadProfile(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // ------------------------------------------------ header
              HeroPanel(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _uploading ? null : _changePhoto,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          UserAvatar(
                            userId: user.id,
                            name: user.name,
                            hasAvatar: user.hasAvatar,
                            version: user.avatarUpdatedAt,
                            size: 96,
                            ring: true,
                          ),
                          if (_uploading)
                            const Positioned.fill(
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.photo_camera_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      user.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.loginId,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _HeaderChip(
                          icon: user.isStudent
                              ? Icons.school_outlined
                              : Icons.co_present_outlined,
                          label: user.role.label,
                        ),
                        if (user.institution != null)
                          _HeaderChip(
                            icon: Icons.apartment_outlined,
                            label: user.institution!,
                          ),
                        if (user.googleLinked)
                          const _HeaderChip(
                            icon: Icons.verified_user_outlined,
                            label: 'Google',
                          ),
                      ],
                    ),
                    if (user.bio != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        user.bio!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (user.mustChangePassword) ...[
                const SizedBox(height: 14),
                Material(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    leading: const Icon(
                      Icons.lock_reset_rounded,
                      color: AppColors.warning,
                    ),
                    title: const Text('Choose your own password'),
                    subtitle: const Text(
                      'You are using a temporary password from your teacher.',
                    ),
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.changePassword),
                  ),
                ),
              ],

              // ------------------------------------------------ account
              const _GroupLabel('Account'),
              _Group(
                children: [
                  _Item(
                    icon: Icons.person_outline_rounded,
                    title: 'Edit profile',
                    subtitle: 'Name, phone, school, about you',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.editProfile),
                  ),
                  _Item(
                    icon: Icons.lock_outline_rounded,
                    title: user.hasPassword
                        ? 'Change password'
                        : 'Set a password',
                    subtitle: user.hasPassword
                        ? null
                        : 'Also sign in with email, not only Google',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.changePassword),
                  ),
                  _Item(
                    icon: Icons.photo_camera_outlined,
                    title: 'Profile photo',
                    subtitle: user.hasAvatar
                        ? 'Change or remove'
                        : 'Add a photo',
                    onTap: _changePhoto,
                  ),
                ],
              ),

              // ------------------------------------------------ classes
              const _GroupLabel('Classes'),
              _Group(
                children: [
                  if (user.isStudent)
                    _Item(
                      icon: Icons.group_add_outlined,
                      title: 'Join a class',
                      subtitle: 'Enter the code from your teacher',
                      onTap: () => showJoinClassSheet(context),
                    )
                  else
                    _Item(
                      icon: Icons.group_add_outlined,
                      title: 'Create a class',
                      subtitle: 'Get a join code for your students',
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.createClass),
                    ),
                  _Item(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    subtitle: user.isStudent
                        ? 'Results, attendance, announcements'
                        : 'Join requests and more',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.notifications),
                  ),
                ],
              ),

              // ------------------------------------------------ app
              const _GroupLabel('About'),
              _Group(
                children: [
                  _Item(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy',
                    subtitle: 'What Assessly stores',
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Privacy'),
                        content: const Text(
                          'Assessly stores your account, classes, attendance and exam results. '
                          'Answer-sheet photos are deleted right after they are read. Students only '
                          'see their own marks. You can delete your account at any time below.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _Item(
                    icon: Icons.info_outline_rounded,
                    title: 'About Assessly',
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'Assessly',
                      applicationVersion: '1.0.0',
                      applicationLegalese:
                          'Classes, attendance, OMR grading and results.',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log out'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _confirmDeleteAccount,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Delete account'),
              ),
              if (user.createdAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Member since ${formatDate(DateTime.parse(user.createdAt!).toLocal(), weekday: false)}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
    child: Text(text.toUpperCase(), style: AppTextStyles.caption),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 60),
          children[i],
        ],
      ],
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    shape: const RoundedRectangleBorder(),
    leading: IconBadge(icon: icon, size: 36),
    title: Text(title, style: AppTextStyles.subtitle),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      color: AppColors.textSecondary,
    ),
  );
}
