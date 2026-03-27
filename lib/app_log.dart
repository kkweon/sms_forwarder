import 'package:flutter/foundation.dart';

import 'file_logger.dart';

FileLogger? _fileLogger;

/// Call once at each Dart entry point (main and backgroundSmsEntryPoint)
/// after [FileLogger.init] resolves.
void initAppLog(FileLogger logger) => _fileLogger = logger;

/// Drop-in replacement for [debugPrint].
///
/// - Always calls [debugPrint] (visible in debug builds / adb logcat).
/// - Also writes to the log file in all build modes so production issues
///   can be diagnosed via the in-app debug log viewer.
void appLog(String message) {
  debugPrint(message);
  _fileLogger?.log(message);
}
