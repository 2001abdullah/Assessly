import 'package:assessly/themes/app_colors.dart';
import 'package:flutter/material.dart';

/// One slide of the onboarding carousel.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.description,
  });

  final String eyebrow;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 15.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
