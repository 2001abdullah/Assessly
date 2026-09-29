import 'package:assessly/routes/app_routes.dart';
import 'package:flutter/material.dart';

import 'onboarding_page.dart';

/// Intro carousel shown to signed-out users; ends at Login / Register.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController pageController = PageController();
  int currentPage = 0;

  static const pages = [
    OnboardingPage(
      eyebrow: 'Build with confidence',
      icon: Icons.assignment_outlined,
      title: 'Exams, organized from the start.',
      description: 'Create an assessment, define its answer key, and keep every scoring rule in one focused workspace.',
    ),
    OnboardingPage(
      eyebrow: 'Scan with precision',
      icon: Icons.document_scanner_outlined,
      title: 'Turn marked sheets into results.',
      description: 'Capture OMR sheets with guided scanning and let Assessly handle identification, answers, and scoring.',
    ),
    OnboardingPage(
      eyebrow: 'Understand outcomes',
      icon: Icons.insights_outlined,
      title: 'Make every result actionable.',
      description: 'Review performance clearly, catch sheets that need attention, and move from paper to insight faster.',
    ),
  ];

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  void _continue() {
    if (currentPage < pages.length - 1) {
      pageController.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D34),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/assessly_hero.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x22040A2A),
                  Color(0x55040A2A),
                  Color(0xF2070B2C),
                ],
                stops: [0, 0.42, 0.76],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 14, 0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.fact_check_outlined,
                        color: Colors.white,
                        size: 25,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Assessly',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pushReplacementNamed(
                          context,
                          AppRoutes.login,
                        ),
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: pageController,
                    onPageChanged: (index) =>
                        setState(() => currentPage = index),
                    children: pages,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 0, 26, 28),
                  child: Row(
                    children: [
                      for (int index = 0; index < pages.length; index++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(right: 7),
                          width: currentPage == index ? 28 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: currentPage == index
                                ? const Color(0xFF75E6FF)
                                : Colors.white.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _continue,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF161A54),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        icon: Icon(
                          currentPage == pages.length - 1
                              ? Icons.login_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(
                          currentPage == pages.length - 1
                              ? 'Get started'
                              : 'Continue',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
