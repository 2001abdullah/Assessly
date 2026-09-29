import 'package:assessly/models/user_model.dart';
import 'package:assessly/screens/account/change_password_screen.dart';
import 'package:assessly/screens/account/edit_profile_screen.dart';
import 'package:assessly/screens/account/notifications_screen.dart';
import 'package:assessly/screens/answer_key_screen.dart';
import 'package:assessly/screens/auth/forgot_password.dart';
import 'package:assessly/screens/auth/login_screen.dart';
import 'package:assessly/screens/auth/registration_screen.dart';
import 'package:assessly/screens/auth/role_select_screen.dart';
import 'package:assessly/screens/create_exam_screen.dart';
import 'package:assessly/screens/exam_details_screen.dart';
import 'package:assessly/screens/exam_list_screen.dart';
import 'package:assessly/screens/home_shell.dart';
import 'package:assessly/screens/onboarding/onboarding_screen.dart';
import 'package:assessly/screens/profile_screen.dart';
import 'package:assessly/screens/result_screen.dart';
import 'package:assessly/screens/results_hub_screen.dart';
import 'package:assessly/screens/scan_omr_screen.dart';
import 'package:assessly/screens/scoring_rules_screen.dart';
import 'package:assessly/screens/splash_screen.dart';
import 'package:assessly/screens/student_results_screen.dart';
import 'package:assessly/screens/teacher/attendance_screen.dart';
import 'package:assessly/screens/teacher/class_detail_screen.dart';
import 'package:assessly/screens/teacher/class_form_screen.dart';
import 'package:assessly/screens/teacher/student_report_screen.dart';
import 'package:flutter/material.dart';

/// Named routes. [home] is the signed-in shell (bottom navigation), which
/// shows the teacher or the student app depending on the user's role.
class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String roleSelect = '/role';
  static const String home = '/home';
  static const String login = '/login'; // argument: UserRole
  static const String register = '/register'; // argument: UserRole
  static const String forgotPassword = '/forgotPassword';

  // Account (both roles)
  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';
  static const String changePassword =
      '/profile/password'; // argument: bool forced
  static const String notifications = '/notifications';

  // Teacher: classes
  static const String createClass = '/classes/new';
  static const String editClass = '/classes/edit'; // argument: class map
  static const String classDetails = '/classes/details'; // argument: class map
  static const String attendance =
      '/classes/attendance'; // argument: class map (+ 'date')
  static const String studentReport =
      '/classes/student'; // argument: {class, student}

  // Teacher: exams
  static const String createNewExam =
      '/createNewExam'; // argument: optional class map
  static const String examDetails = '/examDetails';
  static const String answerKey = '/answerKey';
  static const String scoringRules = '/scoringRules';
  static const String scanOmr = '/scanOmr';
  static const String results = '/results';
  static const String exams = '/exams';
  static const String studentResults = '/studentResults';

  // Both: one result ({resultId, exam?, forStudent?})
  static const String result = '/result';

  static Map<String, dynamic> _map(Object? args) =>
      args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{};

  static Route<dynamic> generateRoute(RouteSettings settings) {
    final args = settings.arguments;
    Widget page;
    switch (settings.name) {
      case splash:
        page = const SplashScreen();
      case onboarding:
        page = const OnboardingScreen();
      case roleSelect:
        page = const RoleSelectScreen();
      case home:
        page = const HomeShell();
      case login:
        page = LoginScreen(role: args is UserRole ? args : UserRole.teacher);
      case register:
        page = RegistrationScreen(
          role: args is UserRole ? args : UserRole.teacher,
        );
      case forgotPassword:
        page = const ForgotPassword();

      case profile:
        page = const ProfileScreen();
      case editProfile:
        page = const EditProfileScreen();
      case changePassword:
        page = ChangePasswordScreen(forced: args == true);
      case notifications:
        page = const NotificationsScreen();

      case createClass:
        page = const ClassFormScreen();
      case editClass:
        page = ClassFormScreen(existing: _map(args));
      case classDetails:
        page = ClassDetailScreen(data: _map(args));
      case attendance:
        page = AttendanceScreen(classData: _map(args));
      case studentReport:
        final a = _map(args);
        page = StudentReportScreen(
          classId: _map(a['class'])['id'].toString(),
          student: _map(a['student']),
        );

      case createNewExam:
        page = CreateExamScreen(classData: args is Map ? _map(args) : null);
      case examDetails:
        page = ExamDetailsScreen(exam: _map(args));
      case answerKey:
        page = AnswerKeyScreen(exam: _map(args));
      case scoringRules:
        page = ScoringRulesScreen(exam: _map(args));
      case scanOmr:
        page = ScanOmrScreen(exam: _map(args));
      case result:
        final a = _map(args);
        page = ResultScreen(
          resultId: a['resultId'].toString(),
          exam: a['exam'] is Map ? _map(a['exam']) : null,
          forStudent: a['forStudent'] == true,
        );
      case results:
        page = const ResultsHubScreen();
      case exams:
        page = const ExamListScreen();
      case studentResults:
        page = StudentResultsScreen(exam: _map(args));
      default:
        page = const SplashScreen();
    }
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }
}
