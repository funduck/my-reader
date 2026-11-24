import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup_sheet/lookup_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'term_support.dart';

const _query = LookupQuery(text: 'cat', mode: LookupMode.enRu);
const _en = ProviderId('dict.en');
const _ru = ProviderId('dict.ru');

/// Senses in English: enough of them to overflow the sheet.
const _longSenses = 30;

class _Provider implements LookupProvider {
  new(this.id, this.mode)
    : info = ProviderInfo(name: id.value, isOnline: false, modes: {mode});

  @override
  final ProviderId id;
  @override
  final ProviderInfo info;
  final LookupMode mode;

  @override
  bool supports(LookupMode m) => m == mode;

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) =>
      throw UnimplementedError();
}

/// One short sense in Russian, [_longSenses] senses in English.
class _Selection implements LookupSelection {
  var _n = 0;

  @override
  Future<LookupOutcome> call({
    required String text,
    LookupMode? mode,
    String? sentence,
    Locator? locator,
    ProviderId? provider,
    CancelToken? cancel,
  }) {
    final ru = mode == LookupMode.enRu;
    return Future.value(
      LookupAnswered(
        event: LookupEvent(
          id: LookupEventId('e${_n++}'),
          query: _query,
          result: LookupResult(
            provider: ru ? _ru : _en,
            senses: ru
                ? const [Sense(text: 'кошка')]
                : [
                    for (var i = 0; i < _longSenses; i++)
                      Sense(text: 'english sense $i'),
                  ],
          ),
          at: DateTime.utc(2026),
        ),
        wordLevel: const WordLevel(CefrLevel.b1),
        skipped: const [],
      ),
    );
  }

  @override
  Future<Term> record(LookupOutcome outcome) async => Term(
    id: const TermId('t'),
    normalized: 'cat',
    language: 'en',
    lookupCount: 1,
    eventIds: [outcome.event.id],
    level: CefrLevel.b1,
  );
}

const _screen = Size(800, 1000);

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lookupSelectionProvider.overrideWithValue(_Selection()),
        ...TermSupport().overrides(),
        lookupProvidersProvider.overrideWithValue([
          _Provider(_ru, LookupMode.enRu),
          _Provider(_en, LookupMode.enEn),
        ]),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(showLookupSheet(context, _query)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

final Finder _toggle = find.byKey(const Key('lookup-mode-toggle'));

/// Height of the sheet without the drag handle above it.
double _height(WidgetTester tester) =>
    tester.getSize(find.byType(DraggableScrollableSheet)).height;

Future<void> _close(WidgetTester tester) async {
  // Past the 2 s on screen, so the record timer is done.
  await tester.pump(minLookupViewDuration);
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('opens at the initial size even for a short answer', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('1. кошка'), findsOneWidget);
    // The share is of the screen below the drag handle.
    final handle =
        tester.getSize(find.byType(BottomSheet)).height - _height(tester);
    expect(handle, greaterThan(0));
    expect(_height(tester), (_screen.height - handle) * lookupSheetInitialSize);
    await _close(tester);
  });

  testWidgets('switching the mode keeps the height; long content scrolls', (
    tester,
  ) async {
    await _open(tester);
    final before = _height(tester);

    await tester.tap(_toggle);
    await tester.pumpAndSettle();

    expect(find.text('1. english sense 0'), findsOneWidget);
    expect(_height(tester), before);
    final last = find.text('$_longSenses. english sense ${_longSenses - 1}');
    expect(last.hitTestable(), findsNothing);

    await tester.scrollUntilVisible(
      last,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(last.hitTestable(), findsOneWidget);
    expect(_height(tester), before);

    // The header scrolls with the content: back to the top to reach it.
    await tester.scrollUntilVisible(
      _toggle,
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(find.text('1. кошка'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a sheet pulled up stays up after switching the mode', (
    tester,
  ) async {
    await _open(tester);
    await tester.drag(find.text('1. кошка'), const Offset(0, -400));
    await tester.pumpAndSettle();
    final pulled = _height(tester);
    expect(pulled, greaterThan(_screen.height * lookupSheetInitialSize));
    expect(pulled, lessThanOrEqualTo(_screen.height * lookupSheetMaxSize));

    await tester.tap(_toggle);
    await tester.pumpAndSettle();

    expect(_height(tester), pulled);
    await _close(tester);
  });
}
