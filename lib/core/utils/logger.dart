import 'dart:developer' as developer;

/// Simple logger utility for debugging
class Logger {
  static const String _tag = 'OxideFilm';
  static bool useConsoleLogs = false; // For CLI debugging

  static void d(String message, {String? tag}) {
    if (useConsoleLogs) print('[DEBUG] [$tag] $message');
    developer.log(
      message,
      name: tag ?? _tag,
      level: 500, // Fine/Debug
    );
  }

  static void i(String message, {String? tag}) {
    if (useConsoleLogs) print('[INFO] [$tag] $message');
    developer.log(
      message,
      name: tag ?? _tag,
      level: 800, // Info
    );
  }

  static void w(String message, {String? tag}) {
    if (useConsoleLogs) print('[WARN] [$tag] $message');
    developer.log(
      message,
      name: tag ?? _tag,
      level: 900, // Warning
    );
  }

  static void e(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (useConsoleLogs) {
      print('[ERROR] [$tag] $message');
      if (error != null) print(error);
      if (stackTrace != null) print(stackTrace);
    }
    developer.log(
      message,
      name: tag ?? _tag,
      level: 1000, // Severe/Error
      error: error,
      stackTrace: stackTrace,
    );
  }
}
