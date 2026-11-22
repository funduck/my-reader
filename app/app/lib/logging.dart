import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

/// A log file larger than this at startup is moved to `<name>.1`.
const int maxLogFileBytes = 1024 * 1024;

final Logger _log = Logger('app');

/// Formats [record] as `HH:mm:ss.mmm LEVEL logger: message`, then the error
/// and the stack trace on separate lines when present.
String formatLogRecord(LogRecord record) {
  final time = record.time.toIso8601String().substring(11, 23);
  final line = StringBuffer(
    '$time ${record.level.name.padRight(7)} '
    '${record.loggerName}: ${record.message}',
  );
  if (record.error != null) line.write('\n  error: ${record.error}');
  if (record.stackTrace != null) line.write('\n${record.stackTrace}');
  return line.toString();
}

/// Sends every `package:logging` record to the console and, if [file] is
/// given, appends it to that file; also logs uncaught errors.
///
/// Call once in `main` before `runApp`. [level] defaults to everything in
/// debug builds and `INFO` and above in release builds.
void setUpLogging({Level? level, File? file}) {
  // Without it go_router adds its own listener and duplicates its records.
  hierarchicalLoggingEnabled = true;
  Logger.root.level = level ?? (kDebugMode ? Level.ALL : Level.INFO);
  final write = file == null ? null : _openLogFile(file);
  Logger.root.onRecord.listen((record) {
    final text = formatLogRecord(record);
    debugPrint(text);
    write?.call(text);
  });

  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    _log.severe(
      'Flutter error: ${details.exceptionAsString()}',
      details.exception,
      details.stack,
    );
    presentError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.severe('Uncaught error', error, stack);
    return true;
  };
  _log.info(
    'Logging at ${Logger.root.level.name}'
    '${file == null ? '' : ', file ${file.path}'}',
  );
}

/// Opens [file] for appending, rotating it first if it is too large.
///
/// Returns null, after logging why, if the file cannot be opened; the
/// console keeps working.
void Function(String)? _openLogFile(File file) {
  final RandomAccessFile out;
  try {
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.lengthSync() > maxLogFileBytes) {
      file.renameSync('${file.path}.1');
    }
    out = file.openSync(mode: FileMode.append);
  } on FileSystemException catch (e) {
    debugPrint('Cannot open log file ${file.path}: $e');
    return null;
  }
  var failed = false;
  return (text) {
    if (failed) return;
    try {
      out.writeStringSync('$text\n');
    } on FileSystemException catch (e) {
      failed = true;
      debugPrint('Log file write failed, file logging is off: $e');
    }
  };
}

/// Logs providers that fail, so errors shown as "Something went wrong" in
/// the UI also reach the log.
final class LoggingProviderObserver extends ProviderObserver {
  /// Creates the observer.
  const new();

  static final Logger _providers = Logger('provider');

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    _providers.warning('${context.provider} failed', error, stackTrace);
  }
}
