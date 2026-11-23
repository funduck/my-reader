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

const _query = LookupQuery(text: 'cat', mode: LookupMode.enEn);
const _a = ProviderId('dict.a');
const _b = ProviderId('dict.b');

class _Provider implements LookupProvider {
  new(this.id, String name)
    : info = ProviderInfo(
        name: name,
        isOnline: false,
        modes: const {LookupMode.enEn},
      );

  @override
  final ProviderId id;
  @override
  final ProviderInfo info;

  @override
  bool supports(LookupMode mode) => mode == LookupMode.enEn;

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) =>
      throw UnimplementedError();
}

/// Answers from the provider asked (or `_a` for the chain) and keeps what was
/// recorded, in order.
class _Selection implements LookupSelection {
  final recorded = <LookupEvent>[];
  var _n = 0;

  @override
  Future<LookupOutcome> call({
    required String text,
    LookupMode? mode,
    String? sentence,
    Locator? locator,
    ProviderId? provider,
    CancelToken? cancel,
  }) async {
    final id = provider ?? _a;
    final event = LookupEvent(
      id: LookupEventId('e${_n++}'),
      query: _query,
      result: LookupResult(
        provider: id,
        senses: [Sense(text: 'a pet from ${id.value}')],
      ),
      at: DateTime.utc(2026),
    );
    return LookupAnswered(
      event: event,
      wordLevel: const WordLevel(CefrLevel.a1),
      skipped: const [],
    );
  }

  @override
  Future<Term> record(LookupOutcome outcome) async {
    recorded.add(outcome.event);
    return Term(
      id: const TermId('t'),
      normalized: 'cat',
      language: 'en',
      lookupCount: recorded.length,
      eventIds: [for (final e in recorded) e.id],
      level: CefrLevel.a1,
    );
  }
}

/// A lookup that never finishes: the sheet stays in the loading state.
class _Never implements LookupSelection {
  @override
  Future<LookupOutcome> call({
    required String text,
    LookupMode? mode,
    String? sentence,
    Locator? locator,
    ProviderId? provider,
    CancelToken? cancel,
  }) => Completer<LookupOutcome>().future;

  @override
  Future<Term> record(LookupOutcome outcome) => throw StateError('recorded');
}

/// Opens the sheet and lets the result appear: it is on screen when this
/// returns, and its 2 s start here.
Future<void> _open(WidgetTester tester, LookupSelection selection) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lookupSelectionProvider.overrideWithValue(selection),
        lookupProvidersProvider.overrideWithValue([
          _Provider(_a, 'Dict A'),
          _Provider(_b, 'Dict B'),
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _close(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
  expect(find.byType(LookupSheet), findsNothing);
}

void main() {
  test('the threshold is 2 seconds', () {
    expect(minLookupViewDuration, const Duration(seconds: 2));
  });

  testWidgets('closed after 1.9 s: nothing is recorded', (tester) async {
    final selection = _Selection();
    await _open(tester, selection);
    expect(find.text('1. a pet from dict.a'), findsOneWidget);

    // The result appeared at the end of _open; the sheet is closed 1.9 s on.
    await tester.pump(const Duration(milliseconds: 1900));
    await _close(tester);
    await tester.pump(const Duration(seconds: 5));

    expect(selection.recorded, isEmpty);
  });

  testWidgets('open for 2 s: one event, and only one', (tester) async {
    final selection = _Selection();
    await _open(tester, selection);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(selection.recorded, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));
    expect(selection.recorded.map((e) => e.id.value), ['e0']);

    await tester.pump(const Duration(seconds: 10));
    expect(selection.recorded, hasLength(1));
  });

  testWidgets('switching the provider after 1 s restarts the 2 s timer', (
    tester,
  ) async {
    final selection = _Selection();
    await _open(tester, selection);
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('lookup-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dict B').last);
    await tester.pump();
    await tester.pump();
    expect(find.text('1. a pet from dict.b'), findsOneWidget);

    // The first result was shown for about 1 s: it is not recorded.
    await tester.pump(const Duration(milliseconds: 1900));
    expect(selection.recorded, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));
    expect(selection.recorded, hasLength(1));
    expect(selection.recorded.single.result.provider, _b);
  });

  testWidgets('no timer runs while the lookup is loading', (tester) async {
    await _open(tester, _Never());
    expect(find.byKey(const Key('lookup-skeleton')), findsOneWidget);

    // A recording would throw StateError in the fake.
    await tester.pump(const Duration(seconds: 10));

    expect(find.byKey(const Key('lookup-skeleton')), findsOneWidget);
  });
}
