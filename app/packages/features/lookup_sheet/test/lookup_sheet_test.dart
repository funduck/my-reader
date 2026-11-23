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

const _query = LookupQuery(text: 'ephemeral', mode: LookupMode.enEn);
const _providerId = ProviderId('fake.dict');

class _FakeProvider implements LookupProvider {
  @override
  ProviderId get id => _providerId;

  @override
  ProviderInfo get info => const ProviderInfo(
    name: 'Fake Dictionary',
    isOnline: false,
    modes: {LookupMode.enEn},
  );

  @override
  bool supports(LookupMode mode) => true;

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) =>
      throw UnimplementedError();
}

/// Fake scenario: returns what [answer] produces; records calls.
class _FakeSelection implements LookupSelection {
  new(this.answer);

  final Future<LookupOutcome> Function() answer;
  final calls = <String>[];
  final modes = <LookupMode?>[];
  final providers = <ProviderId?>[];

  /// Events passed to `record`, in order: what the journal would hold.
  final recorded = <LookupEvent>[];

  @override
  Future<LookupOutcome> call({
    required String text,
    LookupMode? mode,
    String? sentence,
    Locator? locator,
    ProviderId? provider,
    CancelToken? cancel,
  }) {
    calls.add(text);
    modes.add(mode);
    providers.add(provider);
    return answer();
  }

  @override
  Future<Term> record(LookupOutcome outcome) async {
    recorded.add(outcome.event);
    return _term(outcome.level);
  }
}

LookupEvent _event(LookupResult result) => LookupEvent(
  id: const LookupEventId('e1'),
  query: _query,
  result: result,
  at: DateTime.utc(2026),
);

Term _term(CefrLevel level) => Term(
  id: const TermId('t1'),
  normalized: 'ephemeral',
  language: 'en',
  lookupCount: 1,
  eventIds: const [LookupEventId('e1')],
  level: level,
);

LookupOutcome _answered({
  CefrLevel level = CefrLevel.c1,
  bool estimated = false,
}) => LookupAnswered(
  event: _event(
    const LookupResult(
      provider: _providerId,
      transcription: '/ɪˈfem(ə)rəl/',
      senses: [
        Sense(
          text: 'lasting a very short time',
          partOfSpeech: 'adjective',
          examples: ['Fame is ephemeral.'],
        ),
        Sense(text: 'a short-lived thing', partOfSpeech: 'noun'),
      ],
    ),
  ),
  wordLevel: WordLevel(level, estimated: estimated),
  skipped: const [],
);

LookupOutcome _unanswered(List<ProviderAttempt> attempts) => LookupUnanswered(
  event: _event(const LookupResult(provider: _providerId, senses: [])),
  wordLevel: const WordLevel(CefrLevel.unknown),
  failure: ChainFailure(attempts),
);

/// Pumps a page whose button opens the sheet.
Future<_FakeSelection> _open(
  WidgetTester tester,
  Future<LookupOutcome> Function() answer, {
  VoidCallback? onOpenSettings,
}) async {
  final selection = _FakeSelection(answer);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lookupSelectionProvider.overrideWithValue(selection),
        lookupProvidersProvider.overrideWithValue([_FakeProvider()]),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(
                showLookupSheet(
                  context,
                  _query,
                  onOpenSettings: onOpenSettings,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  return selection;
}

void main() {
  testWidgets('shows a skeleton at once, then the answer', (tester) async {
    final completer = Completer<LookupOutcome>();
    final selection = await _open(tester, () => completer.future);
    await tester.pump();

    expect(find.byKey(const Key('lookup-skeleton')), findsOneWidget);
    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('lasting a very short time'), findsNothing);

    completer.complete(_answered());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lookup-skeleton')), findsNothing);
    expect(selection.calls, ['ephemeral']);
    expect(find.text('/ɪˈfem(ə)rəl/'), findsOneWidget);
    expect(find.text('adjective'), findsOneWidget);
    expect(find.text('noun'), findsOneWidget);
    expect(find.text('1. lasting a very short time'), findsOneWidget);
    expect(find.text('2. a short-lived thing'), findsOneWidget);
    expect(find.text('Fame is ephemeral.'), findsOneWidget);
    expect(find.text('C1'), findsOneWidget);
    expect(find.text('Fake Dictionary'), findsOneWidget);
  });

  testWidgets('hides the level chip when the level is unknown', (tester) async {
    await _open(tester, () async => _answered(level: CefrLevel.unknown));
    await tester.pumpAndSettle();

    expect(find.text('1. lasting a very short time'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('marks an estimated level with ≈', (tester) async {
    await _open(
      tester,
      () async => _answered(level: CefrLevel.b2, estimated: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('≈B2'), findsOneWidget);
    expect(find.text('B2'), findsNothing);
  });

  testWidgets('shows a list level without ≈', (tester) async {
    await _open(tester, () async => _answered(level: CefrLevel.b2));
    await tester.pumpAndSettle();

    expect(find.text('B2'), findsOneWidget);
    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('shows "nothing found" when every provider found nothing', (
    tester,
  ) async {
    await _open(
      tester,
      () async => _unanswered(const [
        ProviderAttempt(_providerId, AttemptFailure.notFound),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing found for "ephemeral".'), findsOneWidget);
    expect(find.text('Open settings'), findsNothing);
  });

  testWidgets('shows "no dictionary" with a settings button', (tester) async {
    var opened = 0;
    await _open(
      tester,
      () async => _unanswered(const [
        ProviderAttempt(_providerId, AttemptFailure.unavailable),
      ]),
      onOpenSettings: () => opened++,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No dictionary available'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.byType(LookupSheet), findsNothing);
  });

  testWidgets('shows "no dictionary" when no provider supports the mode', (
    tester,
  ) async {
    await _open(tester, () async => _unanswered(const []));
    await tester.pumpAndSettle();

    expect(find.textContaining('No dictionary available'), findsOneWidget);
  });

  testWidgets('shows an error with retry for an unexpected failure', (
    tester,
  ) async {
    var attempts = 0;
    final selection = await _open(tester, () async {
      attempts++;
      if (attempts == 1) throw StateError('boom');
      return _answered();
    });
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(selection.calls, ['ephemeral', 'ephemeral']);
    expect(find.text('1. lasting a very short time'), findsOneWidget);
  });

  testWidgets('the mode switch repeats the lookup with the other mode', (
    tester,
  ) async {
    final selection = await _open(tester, () async => _answered());
    await tester.pumpAndSettle();
    expect(selection.modes, [LookupMode.enEn]);

    await tester.tap(find.text('EN → RU'));
    await tester.pumpAndSettle();

    expect(selection.calls, ['ephemeral', 'ephemeral']);
    expect(selection.modes, [LookupMode.enEn, LookupMode.enRu]);
    expect(find.text('1. lasting a very short time'), findsOneWidget);
  });

  testWidgets('closing the sheet cancels the running lookup', (tester) async {
    CancelToken? seen;
    final selection = _CancelSpy(onCall: (c) => seen = c);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lookupSelectionProvider.overrideWithValue(selection),
          lookupProvidersProvider.overrideWithValue([_FakeProvider()]),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(showLookupSheet(context, _query)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    expect(seen, isNotNull);
    expect(seen!.isCancelled, isFalse);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byType(LookupSheet), findsNothing);
    expect(seen!.isCancelled, isTrue);
  });
}

class _CancelSpy implements LookupSelection {
  new({required this.onCall});

  final void Function(CancelToken?) onCall;

  @override
  Future<LookupOutcome> call({
    required String text,
    LookupMode? mode,
    String? sentence,
    Locator? locator,
    ProviderId? provider,
    CancelToken? cancel,
  }) {
    onCall(cancel);
    return Completer<LookupOutcome>().future;
  }

  @override
  Future<Term> record(LookupOutcome outcome) => throw UnimplementedError();
}
