import 'package:assessly/models/user_model.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:assessly/widgets/brand.dart';
import 'package:flutter/material.dart';

/// "I'm a teacher" / "I'm a student": decides which login and which app
/// the user gets. Shown after onboarding and after signing out.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  void _choose(BuildContext context, UserRole role) =>
      Navigator.pushNamed(context, AppRoutes.login, arguments: role);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLockup(size: 40)),
                  const SizedBox(height: 28),
                  const Text(
                    'How will you use Assessly?',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heading,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose your role to sign in or create an account.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySecondary,
                  ),
                  const SizedBox(height: 24),
                  _RoleCard(
                    icon: Icons.co_present_outlined,
                    title: "I'm a teacher",
                    subtitle: 'Manage classes, take attendance, scan and grade answer sheets.',
                    color: AppColors.primary,
                    onTap: () => _choose(context, UserRole.teacher),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.school_outlined,
                    title: "I'm a student",
                    subtitle: 'Join your class, see your results, progress and attendance.',
                    color: AppColors.chart[1],
                    onTap: () => _choose(context, UserRole.student),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.title),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppTextStyles.bodySecondary),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
