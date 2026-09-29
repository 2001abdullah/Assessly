import 'package:assessly/models/user_model.dart';
import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/screens/auth/login_screen.dart';
import 'package:assessly/screens/auth/registration_screen.dart';
import 'package:assessly/screens/auth/role_select_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget testApp(Widget child) => ChangeNotifierProvider(
  create: (_) => AuthProvider(),
  child: MaterialApp(home: child),
);

void main() {
  for (final size in <Size>[
    const Size(320, 568),
    const Size(360, 640),
    const Size(480, 854),
    const Size(800, 1280),
  ]) {
    testWidgets('authentication screens fit ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(testApp(const LoginScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('Welcome back'), findsOneWidget);

      await tester.pumpWidget(testApp(const RegistrationScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text('Create your account'), findsOneWidget);

      await tester.pumpWidget(
        testApp(const LoginScreen(role: UserRole.student)),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Student sign in'), findsOneWidget);
      expect(find.text('Email or username'), findsOneWidget);

      await tester.pumpWidget(testApp(const RoleSelectScreen()));
      expect(tester.takeException(), isNull);
      expect(find.text("I'm a teacher"), findsOneWidget);
      expect(find.text("I'm a student"), findsOneWidget);
    });
  }
}
