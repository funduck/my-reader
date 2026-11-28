import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_settings/features_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Store whose writes fail.
class _FailingStore extends FakeSecretStore {
  @override
  Future<void> write(String key, String? value) =>
      Future.error(const FormatException('keychain locked'));
}

const _key = 'abcd-1234-efgh-5678:fx';

void main() {
  Future<void> pump(WidgetTester tester, SecretStore store) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secretStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TranslationSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('deepl-key')), text);
    await tester.tap(find.byKey(const Key('deepl-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('Save writes the key to the store', (tester) async {
    final store = FakeSecretStore();
    await pump(tester, store);
    expect(find.byKey(const Key('deepl-key-none')), findsOneWidget);
    expect(find.widgetWithText(InfoLabel, 'No key saved'), findsOneWidget);

    await save(tester, '  $_key ');

    expect(store.values, {deeplApiKey: _key});
  });

  testWidgets('the field is hidden input and shows only the tail afterwards', (
    tester,
  ) async {
    await pump(tester, FakeSecretStore());
    final field = tester.widget<TextField>(find.byKey(const Key('deepl-key')));
    expect(field.obscureText, isTrue);

    await save(tester, _key);

    expect(
      find.text('Saved key: ••••${_key.substring(_key.length - 4)}'),
      findsOneWidget,
    );
    expect(find.textContaining(_key), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('deepl-key')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('shows the tail of a key saved earlier', (tester) async {
    await pump(tester, FakeSecretStore({deeplApiKey: _key}));
    expect(find.byKey(const Key('deepl-key-saved')), findsOneWidget);
    expect(find.textContaining(_key), findsNothing);
  });

  testWidgets('Remove deletes the key', (tester) async {
    final store = FakeSecretStore({deeplApiKey: _key});
    await pump(tester, store);

    await tester.tap(find.byKey(const Key('deepl-remove')));
    await tester.pumpAndSettle();

    expect(store.values, isEmpty);
    expect(find.byKey(const Key('deepl-key-none')), findsOneWidget);
  });

  testWidgets('Remove is disabled while no key is saved', (tester) async {
    await pump(tester, FakeSecretStore());
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('deepl-remove')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('an empty key is not saved', (tester) async {
    final store = FakeSecretStore();
    await pump(tester, store);
    await save(tester, '   ');
    expect(store.values, isEmpty);
    expect(find.text('Enter the key'), findsOneWidget);
  });

  testWidgets('a short key is fully hidden', (tester) async {
    await pump(tester, FakeSecretStore());
    await save(tester, 'abcd');
    expect(find.text('Saved key: ••••'), findsOneWidget);
  });

  testWidgets('a store failure is shown and the key is not echoed', (
    tester,
  ) async {
    await pump(tester, _FailingStore());
    await save(tester, _key);
    expect(find.textContaining('Cannot save the key'), findsOneWidget);
    // The typed text stays in the field for a retry; no label shows it.
    expect(
      find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(_key)),
      findsNothing,
    );
  });

  testWidgets('shows where to get a free key', (tester) async {
    await pump(tester, FakeSecretStore());
    expect(find.textContaining(deeplKeyHelpUrl), findsOneWidget);
  });
}
