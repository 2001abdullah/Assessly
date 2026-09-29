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
      padding: const EdgeInsets.fromLTRB(26, 110, 26, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 6),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: 29),
          ),
          const SizedBox(height: 22),
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF8DE8FF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.7,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.08,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}
