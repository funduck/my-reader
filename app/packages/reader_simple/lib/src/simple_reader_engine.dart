import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:reader_api/reader_api.dart';

import 'interactions.dart';
import 'position.dart';
import 'reader_style.dart';
import 'reader_view.dart';
import 'throttle.dart';

/// How often [PositionChanged] may be emitted.
const Duration positionInterval = Duration(milliseconds: 500);

/// What the list view tells the engine about itself; implemented by the view.
@internal
abstract interface class ViewportBridge {
  /// The first block that is at least partly on screen and the offset of the
  /// first visible character in it; `null` while nothing is laid out.
  /// `lineEnd` is the end of that line in the block text, when known.
  ({BlockPosition position, int? lineEnd})? firstVisible();
}

/// A chapter shown by the engine and where its list starts.
@immutable
final class ChapterState {
  /// Creates the state; [startBlock] is the block shown first.
  const new({
    required this.ref,
    required this.document,
    required this.startBlock,
    required this.text,
    required this.generation,
    required this.isLast,
    this.startOffset = 0,
  });

  /// The chapter, or `null` for a book without chapters.
  final ChapterRef? ref;

  /// Its content.
  final ContentDocument document;

  /// Index into [ContentDocument.blocks] of the block at the top on open.
  final int startBlock;

  /// Offset in the text of block [startBlock] of the first visible character.
  final int startOffset;

  /// The text of the chapter, for position conversions.
  final ChapterText text;

  /// Whether there is no chapter after this one.
  final bool isLast;

  /// Grows with every chapter switch or [SimpleReaderEngine.goTo]; the view
  /// uses it as a key so that the list is rebuilt at [startBlock].
  final int generation;
}

/// The MVP [ReaderEngine]: a chapter is a lazy list of blocks, one block per
/// list item, drawn with Flutter widgets.
///
/// List layout: item `0` is the "previous chapter" control, items `1..n` are
/// the `n` blocks (block `i` is item `i + 1`), item `n + 1` is the "next
/// chapter" control.
///
/// Tap and selection: a single tap in the view emits [ViewTapped]; a ready
/// selection (a hold, a handle or mouse drag, a double click with a mouse)
/// emits [TextSelected] at once or after "Translate" in the selection
/// toolbar, by `ReaderSettings.translateOnSelect`. The sentence comes from
/// the [TextAnalyzer] given to the constructor, run over the paragraph that
/// holds the text (never over several paragraphs).
///
/// Position: a block index plus a character offset in the block text. The
/// view reports the first visible block and line; the engine turns that into
/// a [Locator] (see `position.dart` for the `engineHint` format) and emits
/// [PositionChanged] at most once per [positionInterval].
class SimpleReaderEngine implements ReaderEngine, TextInteractions {
  /// Creates an engine with default [ReaderSettings]; the analyzer finds
  /// the sentence around a tapped or selected text.
  new({required this._analyzer});

  final TextAnalyzer _analyzer;

  final _events = StreamController<ReaderEvent>.broadcast();
  final _chapter = ValueNotifier<ChapterState?>(null);
  final _settings = ValueNotifier<ReaderStyle>(
    ReaderStyle.fromSettings(const ReaderSettings()),
  );
  final _failure = ValueNotifier<bool>(false);
  late final Throttle _throttle = Throttle(
    interval: positionInterval,
    action: _reportPosition,
  );
  final Set<(int, int)> _selected = {};
  OpenedBook? _book;
  BookId? _bookId;
  ViewportBridge? _bridge;
  Locator? _lastReported;
  final _highlights = ValueNotifier<List<Locator>>(const []);
  int _generation = 0;
  bool _disposed = false;

  /// The chapter on screen, `null` until [load] completes.
  ValueListenable<ChapterState?> get chapter => _chapter;

  /// Current style; changes on [applySettings].
  ValueListenable<ReaderStyle> get style => _settings;

  /// Whether the last chapter switch from the list ends failed.
  ValueListenable<bool> get switchFailed => _failure;

  /// The ranges last passed to [highlight].
  List<Locator> get highlights => _highlights.value;

  /// Changes when [highlight] is called.
  @internal
  Listenable get highlightsListenable => _highlights;

  /// The highlighted ranges of [chapter] by block: block index to
  /// `(start, end)` offsets in the block text. A locator that is not in this
  /// chapter, or whose quote is not found, is skipped.
  @internal
  Map<int, List<(int, int)>> highlightsIn(ChapterState chapter) {
    final ref = chapter.ref;
    final result = <int, List<(int, int)>>{};
    if (ref == null) return result;
    for (final locator in _highlights.value) {
      if (locator.chapter.index != ref.index) continue;
      final range = chapter.text.rangeOfLocator(locator, ref.index);
      if (range == null) continue;
      chapter.text
          .blockRanges(range.start, range.end)
          .forEach((block, ranges) => (result[block] ??= []).addAll(ranges));
    }
    return result;
  }

  /// Loads the bytes of a resource of the current book.
  Future<Uint8List> loadResource(String href) {
    final book = _book;
    if (book == null) throw StateError('load() has not been called');
    return book.resource(href);
  }

  @override
  Widget buildView(BuildContext context) => ReaderView(engine: this);

  @override
  Future<void> load(
    OpenedBook book, {
    required BookId bookId,
    Locator? at,
  }) async {
    _book = book;
    _bookId = bookId;
    await _show(at?.chapter.index ?? 0, locator: at);
  }

  @override
  Future<void> goTo(Locator locator) =>
      _show(locator.chapter.index, locator: locator);

  /// The reading position now, without waiting for the next
  /// [PositionChanged]; `null` until a chapter is on screen.
  Locator? currentLocator() {
    final chapter = _chapter.value;
    final ref = chapter?.ref;
    final bookId = _bookId;
    final visible = _bridge?.firstVisible();
    if (chapter == null || ref == null || bookId == null || visible == null) {
      return null;
    }
    final text = chapter.text;
    final (:position, :lineEnd) = visible;
    return Locator(
      book: bookId,
      chapter: ref,
      progression: text.progressionOf(position),
      quote: text.quoteAt(position, lineEnd: lineEnd),
      engineHint: encodeHint(ref.index, position),
    );
  }

  /// Called by the view when it attaches. Returns the function to call when
  /// the view goes away; it does nothing if another view attached meanwhile.
  @internal
  VoidCallback attachView(ViewportBridge bridge) {
    _bridge = bridge;
    return () {
      if (identical(_bridge, bridge)) _bridge = null;
    };
  }

  /// Called by the view whenever the visible part of the list may have
  /// changed.
  @internal
  void positionTouched() {
    if (!_disposed) _throttle.poke();
  }

  bool _reportPosition() {
    final locator = currentLocator();
    if (locator == null || locator == _lastReported) return false;
    _lastReported = locator;
    _emit(PositionChanged(locator));
    return true;
  }

  @override
  void applySettings(ReaderSettings settings) {
    if (_disposed) return;
    _settings.value = ReaderStyle.fromSettings(settings);
  }

  @override
  void highlight(List<Locator> ranges) {
    if (_disposed) return;
    _highlights.value = List.unmodifiable(ranges);
  }

  @override
  Stream<ReaderEvent> get events => _events.stream;

  /// Switches to the next chapter, if any; called by the list-end control.
  Future<void> openNext() async {
    final current = _chapter.value?.ref;
    if (current == null) return;
    final done = current;
    if (await _switchTo(current.index + 1)) {
      _emit(ChapterFinished(done));
    }
  }

  /// Switches to the end of the previous chapter, if any; called by the
  /// list-end control.
  Future<void> openPrevious() async {
    final current = _chapter.value?.ref;
    if (current == null) return;
    await _switchTo(current.index - 1, progression: 1);
  }

  Future<bool> _switchTo(int index, {double progression = 0}) async {
    try {
      await _show(index, progression: progression);
      _failure.value = false;
      return true;
    } on FormatException {
      _failure.value = true;
    }
    return false;
  }

  /// Shows chapter [index]; the place in it comes from [locator] if given,
  /// else from [progression].
  Future<void> _show(
    int index, {
    Locator? locator,
    double progression = 0,
  }) async {
    final book = _book;
    if (book == null) throw StateError('load() has not been called');
    final spine = book.spine;
    if (spine.isEmpty) {
      _chapter.value = ChapterState(
        ref: null,
        document: const ContentDocument([]),
        text: ChapterText.of(const ContentDocument([])),
        startBlock: 0,
        generation: ++_generation,
        isLast: true,
      );
      return;
    }
    final ref = spine[index.clamp(0, spine.length - 1)];
    final current = _chapter.value;
    final document = current?.ref == ref
        ? current!.document
        : await book.chapter(ref);
    if (_disposed) return;
    final text = current?.ref == ref && identical(current?.document, document)
        ? current!.text
        : ChapterText.of(document);
    final start = locator == null
        ? text.fromProgression(progression)
        : resolveLocator(locator: locator, chapter: ref.index, text: text);
    _chapter.value = ChapterState(
      ref: ref,
      document: document,
      text: text,
      startBlock: start.block,
      startOffset: start.offset,
      generation: ++_generation,
      isLast: ref.index >= spine.length - 1,
    );
  }

  @override
  @internal
  void selectionChanged(TextTarget target, {required bool active}) {
    final key = (target.block, target.base);
    if (active) {
      _selected.add(key);
    } else {
      _selected.remove(key);
    }
  }

  /// Whether any text of the chapter has a non-empty selection.
  @internal
  bool get hasSelection => _selected.isNotEmpty;

  /// A single tap landed at [position] in the view of [size] (T-087).
  @internal
  void viewTapped(Offset position, Size size) =>
      _emit(ViewTapped(position: position, size: size));

  @override
  @internal
  void textSelected(TextTarget target, int start, int end) {
    final text = target.text;
    var from = start.clamp(0, text.length);
    var to = end.clamp(0, text.length);
    while (from < to && text[from].trim().isEmpty) {
      from++;
    }
    while (to > from && text[to - 1].trim().isEmpty) {
      to--;
    }
    if (from >= to) return;
    final at = _locatorOf(target, from, to);
    if (at == null) return;
    _emit(
      TextSelected(
        text: text.substring(from, to),
        at: at,
        sentence: sentenceAround(_analyzer, text, from, to),
      ),
    );
  }

  /// The place of `target.text.substring(start, end)` in the book; the quote
  /// is that text, the hint is the place of its first character.
  Locator? _locatorOf(TextTarget target, int start, int end) {
    final chapter = _chapter.value;
    final ref = chapter?.ref;
    final bookId = _bookId;
    if (chapter == null || ref == null || bookId == null) return null;
    final text = chapter.text;
    final position = BlockPosition(target.block, target.base + start);
    return Locator(
      book: bookId,
      chapter: ref,
      progression: text.progressionOf(position),
      quote: text.quoteAt(position, lineEnd: target.base + end),
      engineHint: encodeHint(ref.index, position),
    );
  }

  void _emit(ReaderEvent event) {
    if (!_disposed) _events.add(event);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _throttle.dispose();
    _bridge = null;
    _chapter.dispose();
    _settings.dispose();
    _failure.dispose();
    _highlights.dispose();
    await _events.close();
  }
}
