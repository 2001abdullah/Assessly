// App entry point.
//
// Builds the app-wide providers (auth, classes, exams, results, the student
// side, notifications and the batch-scan queue), wires them together, and
// installs the global "401 -> sign out" handler. Screens read these providers
// with context.read / context.watch.
import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/providers/batch_scan_provider.dart';
import 'package:assessly/providers/class_provider.dart';
import 'package:assessly/providers/exam_provider.dart';
import 'package:assessly/providers/notification_provider.dart';
import 'package:assessly/providers/results_provider.dart';
import 'package:assessly/providers/student_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/services/authed_http.dart';
import 'package:assessly/services/push_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'themes/app_theme.dart';

/// Lets non-widget code (the 401 and push handlers below) navigate without a
/// context.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushService.init();

  final auth = AuthProvider();
  final classes = ClassProvider();
  final exams = ExamProvider();
  final results = ResultsProvider();
  final student = StudentProvider();
  final notifications = NotificationProvider();
  // Each sheet graded in the background refreshes that exam's results.
  final batch = BatchScanProvider(onResultSaved: results.invalidate);

  // Signing out (manually or on an expired token) clears the previous
  // user's cached data.
  var wasLoggedIn = auth.isLoggedIn;
  auth.addListener(() {
    if (wasLoggedIn && !auth.isLoggedIn) {
      classes.reset();
      exams.reset();
      results.reset();
      student.reset();
      notifications.reset();
      batch.reset();
    }
    wasLoggedIn = auth.isLoggedIn;
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: classes),
        ChangeNotifierProvider.value(value: exams),
        ChangeNotifierProvider.value(value: results),
        ChangeNotifierProvider.value(value: student),
        ChangeNotifierProvider.value(value: notifications),
        ChangeNotifierProvider.value(value: batch),
      ],
      child: const AssesslyApp(),
    ),
  );
}

class AssesslyApp extends StatefulWidget {
  const AssesslyApp({super.key});

  @override
  State<AssesslyApp> createState() => _AssesslyAppState();
}

class _AssesslyAppState extends State<AssesslyApp> {
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    // Any API call answered with 401 (expired/invalid token) signs the user out.
    AuthedHttp.onUnauthorized = () async {
      if (_signingOut || !mounted) return;
      _signingOut = true;
      await context.read<AuthProvider>().logout();
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AppRoutes.roleSelect,
        (route) => false,
      );
      _signingOut = false;
    };

    // Push while the app is open: the system shows nothing, so refresh the
    // inbox and show a banner.
    PushService.onForeground = (message) {
      if (!mounted || !context.read<AuthProvider>().isLoggedIn) return;
      context.read<NotificationProvider>().refresh();
      final title = message.notification?.title;
      if (title == null) return;
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(title),
          action: SnackBarAction(
            label: 'View',
            onPressed: () =>
                navigatorKey.currentState?.pushNamed(AppRoutes.notifications),
          ),
        ),
      );
    };
    // Tapped push: open the notification centre.
    PushService.onOpened = (_) {
      if (!mounted || !context.read<AuthProvider>().isLoggedIn) return;
      context.read<NotificationProvider>().refresh();
      navigatorKey.currentState?.pushNamed(AppRoutes.notifications);
    };
  }

  @override
  void dispose() {
    AuthedHttp.onUnauthorized = null;
    PushService.onForeground = null;
    PushService.onOpened = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Assessly',
      theme: AppTheme.lightTheme,
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}
