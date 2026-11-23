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
const _en = ProviderId('dict.en');
const _ru = ProviderId('dict.ru');
const _ruOnline = ProviderId('online.ru');

class _Provider implements LookupProvider {
  new(this.id, this.mode, {bool online = false})
    : info = ProviderInfo(name: id.value, isOnline: online, modes: {mode});

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

/// Answers `<mode> from <provider>`; modes in [missing] find nothing. When
/// [pendingMode] is set, that mode's lookups never finish.
class _Selection implements LookupSelection {
  new({this.missing = const {}, this.pendingMode});

  final Set<LookupMode> missing;
  final LookupMode? pendingMode;
  final calls = <(LookupMode?, ProviderId?)>[];
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
  }) {
    calls.add((mode, provider));
    if (mode != null && mode == pendingMode) {
      return Completer<LookupOutcome>().future;
    }
    final id = provider ?? (mode == LookupMode.enRu ? _ru : _en);
    final isMissing = missing.contains(mode);
    final event = LookupEvent(
      id: LookupEventId('e${_n++}'),
      query: _query,
      result: LookupResult(
        provider: id,
        senses: isMissing
            ? const []
            : [Sense(text: '${mode?.name} from ${id.value}')],
      ),
      at: DateTime.utc(2026),
    );
    const level = WordLevel(CefrLevel.b1);
    if (isMissing) {
      return Future.value(
        LookupUnanswered(
          event: event,
          wordLevel: level,
          failure: ChainFailure([ProviderAttempt(id, AttemptFailure.notFound)]),
        ),
      );
    }
    return Future.value(
      LookupAnswered(event: event, wordLevel: level, skipped: const []),
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
      level: CefrLevel.b1,
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  _Selection selection,
  List<LookupProvider> providers,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lookupSelectionProvider.overrideWithValue(selection),
        lookupProvidersProvider.overrideWithValue(providers),
      ],
      child: const MaterialApp(
        home: Scaffold(body: LookupSheet(query: _query)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

final Finder _toggle = find.byKey(const Key('lookup-mode-toggle'));

Finder _tooltip(String message) =>
    find.byWidgetPredicate((w) => w is Tooltip && w.message == message);

void main() {
  testWidgets('no provider for the other mode: no toggle', (tester) async {
    final selection = _Selection();
    await _open(tester, selection, [_Provider(_en, LookupMode.enEn)]);

    expect(find.text('1. enEn from dict.en'), findsOneWidget);
    expect(_toggle, findsNothing);
    expect(selection.calls, [(LookupMode.enEn, null)]);
  });

  testWidgets('a provider for the other mode: the press shows its result '
      'without a new call', (tester) async {
    final selection = _Selection();
    await _open(tester, selection, [
      _Provider(_en, LookupMode.enEn),
      _Provider(_ru, LookupMode.enRu),
    ]);
    // The chain and the offline background lookup of the other mode.
    expect(selection.calls, [(LookupMode.enEn, null), (LookupMode.enRu, _ru)]);
    expect(find.text('EN'), findsOneWidget);
    expect(_tooltip('English → English'), findsOneWidget);

    await tester.tap(_toggle);
    await tester.pump();

    expect(find.text('1. enRu from dict.ru'), findsOneWidget);
    expect(find.text('RU'), findsOneWidget);
    expect(_tooltip('English → Russian'), findsOneWidget);
    expect(selection.calls, hasLength(2));

    await tester.tap(_toggle);
    await tester.pump();

    expect(find.text('1. enEn from dict.en'), findsOneWidget);
    expect(selection.calls, hasLength(2));
  });

  testWidgets('the other mode found nothing: the toggle is inactive', (
    tester,
  ) async {
    final selection = _Selection(missing: {LookupMode.enRu});
    await _open(tester, selection, [
      _Provider(_en, LookupMode.enEn),
      _Provider(_ru, LookupMode.enRu),
    ]);

    expect(_toggle, findsOneWidget);
    expect(tester.widget<OutlinedButton>(_toggle).onPressed, isNull);
  });

  testWidgets('while the other mode is pending the toggle is active', (
    tester,
  ) async {
    final selection = _Selection(pendingMode: LookupMode.enRu);
    await _open(tester, selection, [
      _Provider(_en, LookupMode.enEn),
      _Provider(_ru, LookupMode.enRu),
    ]);

    expect(tester.widget<OutlinedButton>(_toggle).onPressed, isNotNull);
  });

  testWidgets('only an online provider for the other mode: no background '
      'call, the press asks for real', (tester) async {
    final selection = _Selection();
    await _open(tester, selection, [
      _Provider(_en, LookupMode.enEn),
      _Provider(_ruOnline, LookupMode.enRu, online: true),
    ]);
    expect(selection.calls, [(LookupMode.enEn, null)]);
    expect(tester.widget<OutlinedButton>(_toggle).onPressed, isNotNull);

    await tester.tap(_toggle);
    await tester.pump();
    await tester.pump();

    expect(selection.calls.last, (LookupMode.enRu, null));
    expect(find.text('1. enRu from dict.ru'), findsOneWidget);
  });

  testWidgets('the other result is recorded only after 2 s on screen', (
    tester,
  ) async {
    final selection = _Selection();
    await _open(tester, selection, [
      _Provider(_en, LookupMode.enEn),
      _Provider(_ru, LookupMode.enRu),
    ]);
    // Nothing is recorded for the background result while it is not shown.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(selection.recorded, isEmpty);

    await tester.tap(_toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1900));
    expect(selection.recorded, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));
    expect(selection.recorded, hasLength(1));
    expect(selection.recorded.single.result.provider, _ru);

    // The first result was on screen for 1.5 s only: it stays out.
    await tester.pump(const Duration(seconds: 10));
    expect(selection.recorded, hasLength(1));
  });

  testWidgets('the translation sits right under the word row', (tester) async {
    await _open(tester, _Selection(), [
      _Provider(_en, LookupMode.enEn),
      _Provider(_ru, LookupMode.enRu),
    ]);

    final word = tester.getRect(find.text('cat'));
    final toggle = tester.getRect(_toggle);
    final level = tester.getRect(find.text('B1'));
    final sense = tester.getRect(find.text('1. enEn from dict.en'));

    // One row: the word, then the level and the toggle at the right edge.
    expect(word.right, lessThanOrEqualTo(level.left));
    expect(level.right, lessThanOrEqualTo(toggle.left));
    expect((toggle.center.dy - word.center.dy).abs(), lessThan(24));
    // The translation is below the row and nothing sits between them.
    final rowBottom = [
      word.bottom,
      toggle.bottom,
      level.bottom,
    ].reduce((a, b) => a > b ? a : b);
    expect(sense.top, greaterThanOrEqualTo(rowBottom));
    expect(sense.top - rowBottom, lessThan(24));
  });
}
