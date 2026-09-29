import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:assessly/main.dart';
import 'package:assessly/providers/auth_provider.dart';

void main() {
  testWidgets('application starts with the configured Material app', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const AssesslyApp(),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Assessly');
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(tester.takeException(), isNull);

    // Let the splash timer complete so no asynchronous work leaks from the
    // smoke test.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });
}
