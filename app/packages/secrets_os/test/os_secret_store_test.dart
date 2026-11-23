import 'package:core_testing/core_testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:secrets_os/secrets_os.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Channel mock that behaves like the native storage.
  final native = <String, String>{};
  final calls = <MethodCall>[];
  PlatformException? failure;

  setUp(() {
    native.clear();
    calls.clear();
    failure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          final error = failure;
          if (error != null) throw error;
          final args = (call.arguments as Map).cast<String, Object?>();
          final key = args['key'] as String?;
          switch (call.method) {
            case 'read':
              return native[key];
            case 'write':
              native[key!] = args['value']! as String;
              return null;
            case 'delete':
              native.remove(key);
              return null;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('OsSecretStore', () {
    secretStoreContract(OsSecretStore.new);
  });

  test('the value is sent to the platform and null deletes the key', () async {
    final store = OsSecretStore();
    await store.write('k', 'v');
    expect(native, {'k': 'v'});
    await store.write('k', null);
    expect(native, isEmpty);
    expect(calls.map((c) => c.method), ['write', 'delete']);
  });

  test('a platform failure is rethrown and the value is not logged', () async {
    failure = PlatformException(code: 'boom');
    final messages = <String>[];
    final previous = Logger.root.level;
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen((r) => messages.add(r.message));
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = previous;
    });

    final store = OsSecretStore();
    await expectLater(
      store.write('k', 'top-secret'),
      throwsA(isA<PlatformException>()),
    );
    expect(messages, isNotEmpty);
    expect(messages.join(), isNot(contains('top-secret')));
  });
}
