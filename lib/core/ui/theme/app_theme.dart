import 'package:flutter/material.dart';

/// Minimal theme so the shell isn't the template default. The full design
/// system (tokens, components, fonts) is F02.
abstract final class AppTheme {
  static const primary = Color(0xFF0272B6);
  static const background = Color(0xFFF8FAFC);
  static const ink = Color(0xFF0F172A);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: background,
      onSurface: ink,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
