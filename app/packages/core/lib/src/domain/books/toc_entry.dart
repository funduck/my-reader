import 'package:meta/meta.dart';

import 'chapter_ref.dart';
import 'list_equality.dart';

/// Entry of the table of contents, possibly with nested entries.
@immutable
final class TocEntry {
  /// Creates an entry; [children] defaults to none.
  const new({
    required this.title,
    required this.chapter,
    this.children = const [],
  });

  /// Heading shown in the table of contents.
  final String title;

  /// Chapter the entry points to.
  final ChapterRef chapter;

  /// Nested entries in reading order.
  final List<TocEntry> children;

  /// Returns a copy with the given fields replaced.
  TocEntry copyWith({
    String? title,
    ChapterRef? chapter,
    List<TocEntry>? children,
  }) => TocEntry(
    title: title ?? this.title,
    chapter: chapter ?? this.chapter,
    children: children ?? this.children,
  );

  @override
  bool operator ==(Object other) =>
      other is TocEntry &&
      other.title == title &&
      other.chapter == chapter &&
      listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(title, chapter, listHash(children));

  @override
  String toString() => 'TocEntry($title, $chapter)';
}

/// Returns the entry of [toc] the reader is in while on chapter
/// [chapterIndex], or `null` before the first entry or for an empty [toc].
///
/// Entries are walked in reading order (a parent, then its children); the
/// result is the last one whose `chapter.index` is at most [chapterIndex].
/// So when several entries point to one chapter the deepest or last wins, and
/// a chapter missing from the table of contents (a cover between entries)
/// belongs to the entry before it.
TocEntry? currentTocEntry(List<TocEntry> toc, int chapterIndex) {
  TocEntry? current;
  void visit(List<TocEntry> entries) {
    for (final entry in entries) {
      if (entry.chapter.index <= chapterIndex) {
        current = entry;
      }
      visit(entry.children);
    }
  }

  visit(toc);
  return current;
}
