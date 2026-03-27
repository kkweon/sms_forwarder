import 'dart:io';

import 'package:path_provider/path_provider.dart';

const _logFileName = 'sms_forwarder_debug.log';
const _maxLogBytes = 200 * 1024; // 200 KB
const _rotateCheckInterval = 50; // check size every N writes

/// File-based logger that works in release builds.
///
/// Call [FileLogger.init] once at app startup (and again in the background
/// isolate entry point). Then pass the instance to [initAppLog].
class FileLogger {
  final File _file;
  int _writeCount = 0;

  FileLogger._(this._file);

  static Future<FileLogger> init() async {
    final dirs = await getExternalStorageDirectories();
    final dir = (dirs != null && dirs.isNotEmpty)
        ? dirs.first
        : await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_logFileName');
    return FileLogger._(file);
  }

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '$timestamp  $message\n';
    try {
      _file.writeAsStringSync(line, mode: FileMode.append);
      _writeCount++;
      if (_writeCount % _rotateCheckInterval == 0) _maybeRotate();
    } catch (_) {
      // Never let logging crash the app.
    }
  }

  Future<String> readAll() async {
    try {
      if (!_file.existsSync()) return '';
      return await _file.readAsString();
    } catch (_) {
      return '';
    }
  }

  Future<void> clear() async {
    try {
      if (_file.existsSync()) await _file.writeAsString('');
    } catch (_) {}
  }

  void _maybeRotate() {
    try {
      final size = _file.lengthSync();
      if (size <= _maxLogBytes) return;
      // Keep the newer half of the file.
      final content = _file.readAsStringSync();
      final half = content.substring(content.length ~/ 2);
      // Start from the next newline so we don't keep a partial line.
      final newlineIdx = half.indexOf('\n');
      final trimmed = newlineIdx >= 0 ? half.substring(newlineIdx + 1) : half;
      _file.writeAsStringSync(trimmed);
    } catch (_) {}
  }
}
