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

const _query = LookupQuery(text: 'cat', mode: LookupMode.enRu);

class _Provider implements LookupProvider {
  new(this.id, String name, this.mode)
    : info = ProviderInfo(name: name, isOnline: false, modes: {mode});

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

class _Selection implements LookupSelection {
  final providers = <ProviderId?>[];
  final modes = <LookupMode?>[];

  @override
  Future<LookupOutcome> call({
    required String text,
    LookupMode? mode,
    String? sentence,
    Locator? locator,
    ProviderId? provider,
    CancelToken? cancel,
  }) {
    providers.add(provider);
    modes.add(mode);
    return Completer<LookupOutcome>().future;
  }

  @override
  Future<Term> record(LookupOutcome outcome) => throw UnimplementedError();
}

void main() {
  const ruA = ProviderId('stardict.a');
  const ruB = ProviderId('stardict.b');
  const en = ProviderId('wiktionary');

  Future<_Selection> open(WidgetTester tester, List<LookupProvider> ps) async {
    final selection = _Selection();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lookupSelectionProvider.overrideWithValue(selection),
          lookupProvidersProvider.overrideWithValue(ps),
        ],
        child: const MaterialApp(
          home: Scaffold(body: LookupSheet(query: _query)),
        ),
      ),
    );
    await tester.pump();
    return selection;
  }

  testWidgets('no picker with a single provider for the mode', (tester) async {
    await open(tester, [
      _Provider(ruA, 'Dict A', LookupMode.enRu),
      _Provider(en, 'Wiktionary', LookupMode.enEn),
    ]);
    expect(find.byKey(const Key('lookup-provider')), findsNothing);
  });

  testWidgets('picking a provider asks only that one', (tester) async {
    final selection = await open(tester, [
      _Provider(ruA, 'Dict A', LookupMode.enRu),
      _Provider(ruB, 'Dict B', LookupMode.enRu),
      _Provider(en, 'Wiktionary', LookupMode.enEn),
    ]);
    // The first call is the chain; the second is the background look at the
    // other mode, offline providers only.
    expect(selection.providers, [null, en]);

    await tester.tap(find.byKey(const Key('lookup-provider')));
    await tester.pumpAndSettle();
    expect(find.text('Wiktionary'), findsNothing);
    await tester.tap(find.text('Dict B').last);
    await tester.pump();
    expect(selection.providers, [null, en, ruB]);

    // Switching the mode drops a pick that does not serve it: the picker of
    // the single English provider is gone and no new lookup is made.
    await tester.tap(find.byKey(const Key('lookup-mode-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('lookup-provider')), findsNothing);
    expect(selection.providers, [null, en, ruB]);
  });
}
