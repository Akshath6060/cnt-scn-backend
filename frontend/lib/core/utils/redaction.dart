/// Privacy-preserving logging (§28).
///
/// Production builds must never emit names, phone numbers, OCR output, or
/// image paths to the system log. This module is the single approved logging
/// entry point; `debugPrint` is banned elsewhere by lint intent.
library;

import 'package:flutter/foundation.dart';

/// Replaces every digit run of length >= 4 with a fixed mask.
String maskDigits(String input) =>
    input.replaceAll(RegExp(r'\d{4,}'), '••••');

/// Reduces a personal name to an initial, e.g. "Anu Sharma" -> "A.S.".
String maskName(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return '${parts.map((p) => p.substring(0, 1).toUpperCase()).join('.')}.';
}

/// Reduces a filesystem path to its extension only.
String maskPath(String path) {
  final dot = path.lastIndexOf('.');
  return dot == -1 ? '<file>' : '<file${path.substring(dot)}>';
}

/// Central logger.
///
/// In release builds only [level] >= [LogLevel.warning] is emitted, and the
/// message is passed through [maskDigits] regardless, so an accidental
/// interpolation of a phone number cannot leak.
enum LogLevel { debug, info, warning, error }

class AppLog {
  const AppLog._();

  /// Set to false in release via [kReleaseMode]; exposed for tests.
  static bool verbose = !kReleaseMode;

  static void debug(String tag, String message) =>
      _emit(LogLevel.debug, tag, message);

  static void info(String tag, String message) =>
      _emit(LogLevel.info, tag, message);

  static void warn(String tag, String message) =>
      _emit(LogLevel.warning, tag, message);

  /// [error] and [stack] are logged only in debug builds.
  static void error(String tag, String message, [Object? error, StackTrace? stack]) {
    _emit(LogLevel.error, tag, message);
    if (verbose && error != null) {
      debugPrint('[$tag] cause: $error');
      if (stack != null) debugPrint(stack.toString());
    }
  }

  static void _emit(LogLevel level, String tag, String message) {
    if (!verbose && level.index < LogLevel.warning.index) return;
    // Defence in depth: mask digit runs even in debug builds.
    debugPrint('[${level.name.toUpperCase()}][$tag] ${maskDigits(message)}');
  }
}
