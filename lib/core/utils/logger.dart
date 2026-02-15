import 'package:flutter/foundation.dart';

/// Lightweight, colour-coded logger.
///
/// Usage:
/// ```dart
/// AppLogger.debug('Fetching SRP', tag: 'SRP');
/// AppLogger.error('Failed to load model', tag: 'ML');
/// ```
class AppLogger {
  AppLogger._();

  static void debug(String message, {String tag = 'APP'}) {
    if (kDebugMode) {
      print('🐛 [$tag] $message');
    }
  }

  static void info(String message, {String tag = 'APP'}) {
    if (kDebugMode) {
      print('ℹ️ [$tag] $message');
    }
  }

  static void warn(String message, {String tag = 'APP'}) {
    if (kDebugMode) {
      print('⚠️ [$tag] $message');
    }
  }

  static void error(String message, {String tag = 'APP', Object? error}) {
    if (kDebugMode) {
      print('❌ [$tag] $message');
      if (error != null) print('   └─ $error');
    }
  }
}
