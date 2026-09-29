import 'dart:async';

import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

/// First screen: restores the saved session, then opens Home (signed in) or Onboarding.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final loggedIn = await context.read<AuthProvider>().restoreSession();
      if (!mounted) return;

      if (loggedIn) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/assessly_hero.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33040A2A), Color(0xE6080C32)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Assessly',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Assessment, from paper to insight.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 34),
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Color(0xFF75E6FF),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
