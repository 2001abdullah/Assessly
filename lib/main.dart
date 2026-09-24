import 'package:assessly/providers/app_provider.dart';
import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/services/authed_http.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'themes/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: ((_) => AppProvider())),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
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
        AppRoutes.login,
        (route) => false,
      );
      _signingOut = false;
    };
  }

  @override
  void dispose() {
    AuthedHttp.onUnauthorized = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Assessly',
      theme: AppTheme.lightTheme,
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}
