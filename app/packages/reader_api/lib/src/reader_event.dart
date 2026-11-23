import 'package:core/domain_books.dart';
import 'package:meta/meta.dart';

import 'reader_engine.dart';

/// Something that happened in the reader and the app may react to.
///
/// Sealed: handle it with an exhaustive `switch`.
@immutable
sealed class ReaderEvent {
  const new();
}

/// The reading position changed (scroll or [ReaderEngine.goTo]); emitted
/// for saving progress.
final class PositionChanged extends ReaderEvent {
  /// Creates the event for the new position [locator].
  const new(this.locator);

  /// Current position, the start of the visible text.
  final Locator locator;

  @override
  bool operator ==(Object other) =>
      other is PositionChanged && other.locator == locator;

  @override
  int get hashCode => Object.hash(PositionChanged, locator);
}

/// The user selected a word or phrase (T-1).
final class TextSelected extends ReaderEvent {
  /// Creates the event.
  const new({required this.text, required this.at, required this.sentence});

  /// Selected text as shown.
  final String text;

  /// Where the selection starts in the book.
  final Locator at;

  /// The sentence that contains the selection, as context for history.
  final String sentence;

  @override
  bool operator ==(Object other) =>
      other is TextSelected &&
      other.text == text &&
      other.at == at &&
      other.sentence == sentence;

  @override
  int get hashCode => Object.hash(TextSelected, text, at, sentence);
}

/// The user held a word (about 500 ms, T-085) to look it up; the word is
/// taken whole.
final class WordTapped extends ReaderEvent {
  /// Creates the event.
  const new({required this.word, required this.at, required this.sentence});

  /// The tapped word as shown, without surrounding punctuation.
  final String word;

  /// Where the word starts in the book.
  final Locator at;

  /// The sentence that contains the word, as context for history.
  final String sentence;

  @override
  bool operator ==(Object other) =>
      other is WordTapped &&
      other.word == word &&
      other.at == at &&
      other.sentence == sentence;

  @override
  int get hashCode => Object.hash(WordTapped, word, at, sentence);
}

/// The user reached the end of a chapter (basis for the chapter test, L-3).
final class ChapterFinished extends ReaderEvent {
  /// Creates the event for [chapter].
  const new(this.chapter);

  /// The chapter that was finished.
  final ChapterRef chapter;

  @override
  bool operator ==(Object other) =>
      other is ChapterFinished && other.chapter == chapter;

  @override
  int get hashCode => Object.hash(ChapterFinished, chapter);
}
