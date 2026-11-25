import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:flutter/widgets.dart';

import 'reader_event.dart';
import 'reader_highlights.dart';
import 'reader_settings.dart';

/// A renderer of an opened book.
///
/// The `reader` feature knows only this interface; the concrete engine is
/// created by a [ReaderEngineFactory] supplied by the app. Lifecycle:
/// construct, [load], use, [dispose]. Calls other than [load], [events] and
/// [dispose] before [load] completes are a programming error.
abstract interface class ReaderEngine {
  /// Builds the widget that shows the book; it may be called many times and
  /// must show the same state.
  Widget buildView(BuildContext context);

  /// Shows [book], starting at [at] or at the beginning when `null`.
  ///
  /// [bookId] is the id of [book] in the library; the engine puts it into
  /// every [Locator] it reports, because an [OpenedBook] does not know it.
  ///
  /// The engine does not close [book]; the caller owns it and closes it after
  /// [dispose].
  Future<void> load(OpenedBook book, {required BookId bookId, Locator? at});

  /// Scrolls to [locator]. A locator the engine cannot resolve falls back to
  /// the nearest known position, using its `TextQuote` when present.
  Future<void> goTo(Locator locator);

  /// Applies display settings (R-3) and keeps the current position.
  void applySettings(ReaderSettings settings);

  /// Marks places and words in the text by kind; replaces the previous set.
  /// [ReaderHighlights.none] clears all highlights. Where several kinds meet
  /// on one word, the kind declared first in [HighlightKind] is drawn.
  void highlight(ReaderHighlights highlights);

  /// Broadcast stream of [ReaderEvent]s; closed by [dispose].
  Stream<ReaderEvent> get events;

  /// Releases resources and closes [events]. Safe to call once.
  Future<void> dispose();
}

/// Creates a fresh [ReaderEngine]; the app chooses the concrete engine.
typedef ReaderEngineFactory = ReaderEngine Function();
