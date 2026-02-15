import 'package:flutter/material.dart';

/// Application theme configuration.
///
/// Add your colour tokens, text styles and component themes here.
/// Reference this in `MaterialApp.router(theme: AppTheme.light)`.
class AppTheme {
  AppTheme._();

  // ── Light Theme ───────────────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
    // TODO: customise further (cards, inputs, typography, etc.)
  );

  // ── Dark Theme ────────────────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.dark,
    ),
    // TODO: customise further
  );
}
