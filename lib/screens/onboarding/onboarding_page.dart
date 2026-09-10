import 'package:flutter/material.dart';
import '../../themes/app_colors.dart';
import '../../themes/app_theme.dart';
import '../../themes/app_text_styles.dart';

class OnboardingPage extends StatelessWidget {

  final IconData icon;
  final String title;
  final String description;


  const OnboardingPage({super.key,
  required this.icon,
  required this.title,
  required this.description
  });

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsetsGeometry.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle
          ),
          child: Icon(
            icon,
            size: 90,
            color: AppColors.primary,
          ),
        ),

        SizedBox(height: 40,),

        Text(
          title,
          style: AppTextStyles.heading.copyWith(
            fontSize: 26
          ),
          textAlign: TextAlign.center,
        ),

        Text(description,
        style: AppTextStyles.bodySecondary,
        textAlign: TextAlign.center,)
      ],
    ),
    );

  }
}
