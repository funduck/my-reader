import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026);
}

void main() {
  test('an unwired port throws', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(bookRepositoryProvider),
      throwsA(anyOf(isA<PortNotWiredError>(), isA<ProviderException>())),
    );
  });

  test('the dictionary library port is unwired until bootstrap', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(dictionaryLibraryProvider),
      throwsA(anyOf(isA<PortNotWiredError>(), isA<ProviderException>())),
    );
  });

  test('the phrase journal port is unwired until bootstrap', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(phraseJournalProvider),
      throwsA(anyOf(isA<PortNotWiredError>(), isA<ProviderException>())),
    );
  });

  test('the cheat sheet log port is unwired until bootstrap', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(cheatSheetLogProvider),
      throwsA(anyOf(isA<PortNotWiredError>(), isA<ProviderException>())),
    );
  });

  test('an override supplies the port', () {
    final container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(_Clock())],
    );
    addTearDown(container.dispose);
    expect(container.read(clockProvider).now(), DateTime.utc(2026));
  });
}
