import 'package:flutter/material.dart';

/// Slate + teal palette. Screens use these names, never raw hex values, so
/// the whole app re-themes from here.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF0D9488); // teal 600
  static const Color primaryDark = Color(0xFF134E4A); // teal 900
  static const Color secondary = Color(0xFF0891B2); // cyan 600
  static const Color primarySoft = Color(0xFFE6F6F4);

  /// Deep slate used for headers and the splash screen.
  static const Color ink = Color(0xFF0F172A); // slate 900
  static const Color inkSoft = Color(0xFF1E293B); // slate 800

  // Surfaces
  static const Color background = Color(0xFFF6F8FA);
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF1F5F9);

  // Text
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textOnDark = Colors.white;

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color successSoft = Color(0xFFDCFCE7);
  static const Color error = Color(0xFFDC2626);
  static const Color errorSoft = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color neutral = Color(0xFF64748B);
  static const Color neutralSoft = Color(0xFFE2E8F0);
  static const Color info = Color(0xFF0284C7);
  static const Color infoSoft = Color(0xFFE0F2FE);

  static const Color border = Color(0xFFE2E8F0);

  /// Chart series colours, in order.
  static const List<Color> chart = [
    primary,
    Color(0xFF6366F1), // indigo
    Color(0xFFF59E0B), // amber
    Color(0xFFEC4899), // pink
    Color(0xFF22C55E), // green
    Color(0xFF64748B), // slate
  ];

  /// Header gradient used on hero sections across the app: slate into teal.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, primaryDark, primary],
    stops: [0.0, 0.55, 1.0],
  );
}
