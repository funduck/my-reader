import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:reader_api/reader_api.dart';

import 'reader_style.dart';
import 'reader_view.dart';

/// A chapter shown by the engine and where its list starts.
@immutable
final class ChapterState {
  /// Creates the state; [startBlock] is the block shown first.
  const new({
    required this.ref,
    required this.document,
    required this.startBlock,
    required this.generation,
    required this.isLast,
  });

  /// The chapter, or `null` for a book without chapters.
  final ChapterRef? ref;

  /// Its content.
  final ContentDocument document;

  /// Index into [ContentDocument.blocks] of the block at the top on open.
  final int startBlock;

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
/// chapter" control. Position tracking, `Locator` conversion, tap and
/// selection events are built on this layout by later tasks (T-017, T-018).
class SimpleReaderEngine implements ReaderEngine {
  /// Creates an engine with default [ReaderSettings].
  new();

  final _events = StreamController<ReaderEvent>.broadcast();
  final _chapter = ValueNotifier<ChapterState?>(null);
  final _settings = ValueNotifier<ReaderStyle>(
    ReaderStyle.fromSettings(const ReaderSettings()),
  );
  final _failure = ValueNotifier<bool>(false);
  OpenedBook? _book;
  List<Locator> _highlights = const [];
  int _generation = 0;
  bool _disposed = false;

  /// The chapter on screen, `null` until [load] completes.
  ValueListenable<ChapterState?> get chapter => _chapter;

  /// Current style; changes on [applySettings].
  ValueListenable<ReaderStyle> get style => _settings;

  /// Whether the last chapter switch from the list ends failed.
  ValueListenable<bool> get switchFailed => _failure;

  /// The ranges last passed to [highlight]; drawing them is not done yet.
  List<Locator> get highlights => _highlights;

  /// Loads the bytes of a resource of the current book.
  Future<Uint8List> loadResource(String href) {
    final book = _book;
    if (book == null) throw StateError('load() has not been called');
    return book.resource(href);
  }

  @override
  Widget buildView(BuildContext context) => ReaderView(engine: this);

  @override
  Future<void> load(OpenedBook book, {Locator? at}) async {
    _book = book;
    await _show(at?.chapter.index ?? 0, progression: at?.progression ?? 0);
  }

  @override
  Future<void> goTo(Locator locator) =>
      _show(locator.chapter.index, progression: locator.progression);

  @override
  void applySettings(ReaderSettings settings) {
    if (_disposed) return;
    _settings.value = ReaderStyle.fromSettings(settings);
  }

  @override
  void highlight(List<Locator> ranges) {
    _highlights = List.unmodifiable(ranges);
  }

  @override
  Stream<ReaderEvent> get events => _events.stream;

  /// Switches to the next chapter, if any; called by the list-end control.
  Future<void> openNext() async {
    final current = _chapter.value?.ref;
    if (current == null) return;
    final done = current;
    if (await _switchTo(current.index + 1, progression: 0)) {
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

  Future<bool> _switchTo(int index, {required double progression}) async {
    try {
      await _show(index, progression: progression);
      _failure.value = false;
      return true;
    } on FormatException {
      _failure.value = true;
    }
    return false;
  }

  Future<void> _show(int index, {required double progression}) async {
    final book = _book;
    if (book == null) throw StateError('load() has not been called');
    final spine = book.spine;
    if (spine.isEmpty) {
      _chapter.value = ChapterState(
        ref: null,
        document: const ContentDocument([]),
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
    final count = document.blocks.length;
    _chapter.value = ChapterState(
      ref: ref,
      document: document,
      startBlock: count == 0
          ? 0
          : (progression * count).floor().clamp(0, count - 1),
      generation: ++_generation,
      isLast: ref.index >= spine.length - 1,
    );
  }

  void _emit(ReaderEvent event) {
    if (!_disposed) _events.add(event);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _chapter.dispose();
    _settings.dispose();
    _failure.dispose();
    await _events.close();
  }
}
