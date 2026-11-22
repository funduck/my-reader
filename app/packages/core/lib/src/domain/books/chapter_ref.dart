import 'package:meta/meta.dart';

/// Renderer-neutral reference to a chapter: `href` inside the book plus the
/// zero-based chapter index.
@immutable
final class ChapterRef {
  /// Creates a reference to the chapter at [href] with the given [index].
  const new({required this.href, required this.index});

  /// Restores a reference from [toJson] output.
  factory fromJson(Map<String, Object?> json) =>
      ChapterRef(href: json['href']! as String, index: json['index']! as int);

  /// Path (and optional fragment) of the chapter inside the book container.
  final String href;

  /// Zero-based position of the chapter in reading order.
  final int index;

  /// Returns a copy with the given fields replaced.
  ChapterRef copyWith({String? href, int? index}) =>
      ChapterRef(href: href ?? this.href, index: index ?? this.index);

  /// JSON form for storage.
  Map<String, Object?> toJson() => {'href': href, 'index': index};

  @override
  bool operator ==(Object other) =>
      other is ChapterRef && other.href == href && other.index == index;

  @override
  int get hashCode => Object.hash(href, index);

  @override
  String toString() => 'ChapterRef($href, #$index)';
}
