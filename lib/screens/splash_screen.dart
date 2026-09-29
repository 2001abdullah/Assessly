import 'dart:async';

import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/widgets/brand.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// First screen: restores the saved session, then opens the signed-in user's
/// home (teacher or student) or the onboarding carousel.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Timer(const Duration(milliseconds: 1200), () async {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final loggedIn = await auth.restoreSession();
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        loggedIn ? AppRoutes.home : AppRoutes.onboarding,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: InkBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                const Spacer(flex: 3),
                const SheetIllustration(width: 170),
                const Spacer(flex: 2),
                const BrandLockup(onDark: true, size: 46),
                const SizedBox(height: 12),
                Text(
                  'Exams, attendance and results in one place.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 15,
                  ),
                ),
                const Spacer(flex: 2),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
