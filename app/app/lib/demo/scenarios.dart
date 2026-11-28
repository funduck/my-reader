import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:features_settings/features_settings.dart';
import 'package:lookup_sheet/lookup_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

import '../router.dart';
import 'demo_data.dart';

/// What a scenario does after the first frame, with the context of the app
/// navigator (to show sheets over the start screen).
typedef DemoAction = Future<void> Function(BuildContext navigator);

/// A ready-made situation of the app: where it starts, with which profile,
/// and what is shown on top after the first frame.
///
/// The data are always the demo data (`demo_data.dart`), fresh for every
/// start.
final class DemoScenario {
  /// Creates a scenario.
  const new({
    required this.id,
    required this.title,
    required this.location,
    this.profile = const UserProfile(),
    this.afterFirstFrame,
    this.highlights = ReaderHighlights.none,
  });

  /// Value of `--dart-define=SCENARIO=<id>`.
  final String id;

  /// Line in the list of scenarios.
  final String title;

  /// Initial route.
  final String location;

  /// Profile the app starts with.
  final UserProfile profile;

  /// Action after the first frame; `null` — none.
  final DemoAction? afterFirstFrame;

  /// Highlights always shown in the reader on top of those of the screen.
  final ReaderHighlights highlights;
}

/// Locator of [quote] in the first chapter of the demo book.
Locator demoLocator(String quote) => Locator(
  book: demoBookId,
  chapter: const ChapterRef(href: 'chapter1.xhtml', index: 0),
  progression: 0,
  quote: TextQuote(exact: quote),
);

/// The sentence of the first chapter with [word], for the lookup context.
String demoSentence(String word) {
  final text = demoChapters.first.replaceAll('\n', ' ');
  final at = text.indexOf(word);
  if (at < 0) return word;
  final start = text.lastIndexOf(RegExp(r'[.!?]\s'), at);
  final end = text.indexOf(RegExp('[.!?]'), at);
  return text.substring(start < 0 ? 0 : start + 2, end < 0 ? null : end + 1);
}

DemoAction _lookup(String text, LookupMode mode) =>
    (navigator) => showLookupSheet(
      navigator,
      LookupQuery(
        text: text,
        mode: mode,
        sentence: demoSentence(text),
        locator: demoLocator(text),
      ),
    );

final String _reader = Routes.readerAt(demoBookId.value);

/// All scenarios, in the order of the list.
final List<DemoScenario> demoScenarios = [
  const DemoScenario(
    id: 'library',
    title: 'Library with the demo book',
    location: Routes.library,
  ),
  DemoScenario(id: 'reader', title: 'Reader, chapter 1', location: _reader),
  DemoScenario(
    id: 'lookup_word',
    title: 'Reader + word sheet, EN → RU (short)',
    location: _reader,
    profile: const UserProfile(mode: LookupMode.enRu),
    afterFirstFrame: _lookup('lantern', LookupMode.enRu),
  ),
  DemoScenario(
    id: 'lookup_word_en',
    title: 'Reader + word sheet, EN → EN (long)',
    location: _reader,
    afterFirstFrame: _lookup('lantern', LookupMode.enEn),
  ),
  DemoScenario(
    id: 'lookup_not_found',
    title: 'Reader + word sheet, nothing found',
    location: _reader,
    afterFirstFrame: _lookup('harbour', LookupMode.enEn),
  ),
  DemoScenario(
    id: 'lookup_phrase',
    title: 'Reader + phrase sheet',
    location: _reader,
    profile: const UserProfile(mode: LookupMode.enRu),
    afterFirstFrame: _lookup(demoPhrase, LookupMode.enRu),
  ),
  DemoScenario(
    id: 'reader_highlights',
    title:
        'Reader, every kind of highlight (T-113; the recent one pulses once)',
    location: _reader,
    highlights: demoAllHighlights,
  ),
  DemoScenario(
    id: 'reader_pulse',
    title: 'Reader, the pulse of a just translated word (T-124)',
    location: _reader,
    highlights: demoPulseHighlights,
  ),
  DemoScenario(
    id: 'cheatsheet',
    title: 'Cheat sheet of the demo book',
    location: Routes.cheatsheetFor(demoBookId.value),
  ),
  const DemoScenario(
    id: 'settings',
    title: 'Settings',
    location: Routes.settings,
  ),
  DemoScenario(
    id: 'color_picker',
    title: 'Settings + colour wheel (day background)',
    location: Routes.settings,
    afterFirstFrame: (navigator) => showColorPicker(
      navigator,
      title: 'Day palette: background',
      initial: const UserProfile().display.day.background,
    ),
  ),
];

/// The scenario with [id], or `null`.
DemoScenario? demoScenarioById(String id) {
  for (final s in demoScenarios) {
    if (s.id == id) return s;
  }
  return null;
}

/// Every kind of highlight in the first chapter of the demo book; "lantern"
/// is both a cheat sheet word and a difficult one.
final ReaderHighlights demoAllHighlights = ReaderHighlights(
  ranges: {
    HighlightKind.focus: [demoLocator('stories')],
    HighlightKind.recent: [demoLocator('dusty')],
  },
  words: const {
    HighlightKind.lookedUp: {'reluctant'},
    HighlightKind.cheatSheet: {'lantern', 'harbour'},
    HighlightKind.difficult: {'lantern', 'mischievous', 'threshold', 'weary'},
  },
);

/// One just translated word, "dusty": it pulses for 2.5 s when the reader
/// opens and then leaves (T-124). To see it again, open the scenario again or
/// translate a word.
final ReaderHighlights demoPulseHighlights = ReaderHighlights(
  ranges: {
    HighlightKind.recent: [demoLocator('dusty')],
  },
);
