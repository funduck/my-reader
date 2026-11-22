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
