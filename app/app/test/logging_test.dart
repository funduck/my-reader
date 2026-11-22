import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:my_reader_app/logging.dart';

void main() {
  test('formatLogRecord puts time, level, logger and message on one line', () {
    final record = LogRecord(Level.INFO, 'hello', 'ImportBook');
    expect(
      formatLogRecord(record),
      matches(RegExp(r'^\d\d:\d\d:\d\d\.\d{3} INFO    ImportBook: hello$')),
    );
  });

  test('formatLogRecord adds the error and the stack trace', () {
    final record = LogRecord(
      Level.WARNING,
      'failed',
      'x',
      const FormatException('bad'),
      StackTrace.fromString('#0 main'),
    );
    final text = formatLogRecord(record);
    expect(text, contains('\n  error: FormatException: bad'));
    expect(text, endsWith('\n#0 main'));
  });

  test('LoggingProviderObserver logs a failing provider', () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    final failing = FutureProvider<int>(
      (ref) => Future.error(StateError('boom')),
      name: 'failing',
    );
    final container = ProviderContainer(
      observers: const [LoggingProviderObserver()],
    );
    addTearDown(container.dispose);
    final sub2 = container.listen(failing, (_, _) {});
    addTearDown(sub2.close);
    await container.read(failing.future).then((_) {}, onError: (Object _) {});

    final record = records.singleWhere((r) => r.loggerName == 'provider');
    expect(record.level, Level.WARNING);
    expect(record.message, contains('failing'));
    expect(record.error, isA<StateError>());
  });
}
