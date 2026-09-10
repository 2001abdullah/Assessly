
import 'package:assessly/providers/app_provider.dart';
import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'themes/app_theme.dart';



void main() async {
 WidgetsFlutterBinding.ensureInitialized();

  runApp(MultiProvider(providers:
  [ChangeNotifierProvider(
      create: ((_) => AppProvider())
  ),
    ChangeNotifierProvider(create: (_)=>AuthProvider())
  ],
  child: const AssesslyApp(),
  )
  );
}

class AssesslyApp extends StatefulWidget {
  const AssesslyApp({super.key});

  @override
  State<AssesslyApp> createState() => _AssesslyAppState();
}

class _AssesslyAppState extends State<AssesslyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Assessly',
      theme: AppTheme.lightTheme,
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}

