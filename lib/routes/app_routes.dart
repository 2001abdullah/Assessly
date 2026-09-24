import 'package:assessly/screens/answer_key_screen.dart';
import 'package:assessly/screens/auth/forgot_password.dart';
import 'package:assessly/screens/auth/login_screen.dart';
import 'package:assessly/screens/auth/registration_screen.dart';
import 'package:assessly/screens/create_exam_screen.dart';
import 'package:assessly/screens/exam_details_screen.dart';
import 'package:assessly/screens/home_screen.dart';
import 'package:assessly/screens/profile_screen.dart';
import 'package:assessly/screens/onboarding/onboarding_screen.dart';
import 'package:assessly/screens/scoring_rules_screen.dart';
import 'package:assessly/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:assessly/screens/scan_omr_screen.dart';
import 'package:assessly/screens/result_screen.dart';
import 'package:assessly/screens/exam_list_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgotPassword';
  static const String createNewExam = '/createNewExam';
  static const String examDetails = '/examDetails';
  static const String answerKey = '/answerKey';
  static const String scoringRules = '/scoringRules';
  static const String scanOmr = '/scanOmr';
  static const String result = '/result';
  static const String exams = '/exams';
  static const String profile = '/profile';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());

      case onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());

      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());

      case profile:
        return MaterialPageRoute(builder: (_) => const ProfileScreen());

      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case register:
        return MaterialPageRoute(builder: (_) => const RegistrationScreen());

      case forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPassword());

      case createNewExam:
        return MaterialPageRoute(builder: (_) => const CreateExamScreen());

      case examDetails:
        final exam = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(builder: (_) => ExamDetailsScreen(exam: exam));
      case answerKey:
        final exam = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(builder: (_) => AnswerKeyScreen(exam: exam));
      case scoringRules:
        final exam = settings.arguments as Map<String, dynamic>;

        return MaterialPageRoute(
          builder: (_) => ScoringRulesScreen(exam: exam),
        );

      case scanOmr:
        final exam = settings.arguments as Map<String, dynamic>;

        return MaterialPageRoute(builder: (_) => ScanOmrScreen(exam: exam));
      case result:
        final args = settings.arguments as Map<String, dynamic>;

        final exam = args['exam'] as Map<String, dynamic>;

        final scoreResult = args['scoreResult'] as Map<String, dynamic>;

        return MaterialPageRoute(
          builder: (_) => ResultScreen(exam: exam, scoreResult: scoreResult),
        );

      case exams:
        return MaterialPageRoute(builder: (_) => const ExamListScreen());

      default:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
    }
  }
}
