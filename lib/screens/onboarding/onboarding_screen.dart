import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/widgets/brand.dart';
import 'package:flutter/material.dart';

import 'onboarding_page.dart';

/// Intro carousel shown to signed-out users; ends at the role chooser.
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
      eyebrow: 'For teachers',
      icon: Icons.groups_2_outlined,
      title: 'Your classes, organised.',
      description: 'Create classes, enrol students with a code, take attendance and post announcements.',
    ),
    OnboardingPage(
      eyebrow: 'Scan & grade',
      icon: Icons.document_scanner_outlined,
      title: 'Paper sheets to results in seconds.',
      description: 'Print an answer sheet for each exam, scan it with your phone and Assessly marks it for you.',
    ),
    OnboardingPage(
      eyebrow: 'For students',
      icon: Icons.insights_outlined,
      title: 'See how you are doing.',
      description: 'Get your results the moment they are published, track your progress and your attendance.',
    ),
  ];

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  void _finish() =>
      Navigator.pushReplacementNamed(context, AppRoutes.roleSelect);

  void _continue() {
    if (currentPage < pages.length - 1) {
      pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = currentPage == pages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: InkBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                child: Row(
                  children: [
                    const BrandLockup(onDark: true, size: 34),
                    const Spacer(),
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SheetIllustration(width: 150),
              Expanded(
                child: PageView(
                  controller: pageController,
                  onPageChanged: (index) => setState(() => currentPage = index),
                  children: pages,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    for (int index = 0; index < pages.length; index++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 6),
                        width: currentPage == index ? 24 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: currentPage == index
                              ? AppColors.primary
                              : Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _continue,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                      ),
                      icon: Icon(
                        last
                            ? Icons.login_rounded
                            : Icons.arrow_forward_rounded,
                      ),
                      label: Text(last ? 'Get started' : 'Next'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
