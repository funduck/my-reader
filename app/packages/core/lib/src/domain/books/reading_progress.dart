import 'package:meta/meta.dart';

import 'locator.dart';

/// Where the reader stopped in a book.
@immutable
final class ReadingProgress {
  /// Creates progress; [percent] is the whole-book fraction 0..1.
  const new({
    required this.locator,
    required this.percent,
    required this.updatedAt,
  }) : assert(percent >= 0 && percent <= 1, 'percent must be within 0..1');

  /// Last reading position.
  final Locator locator;

  /// Fraction of the whole book read, 0..1.
  final double percent;

  /// When the position was saved.
  final DateTime updatedAt;

  /// Returns a copy with the given fields replaced.
  ReadingProgress copyWith({
    Locator? locator,
    double? percent,
    DateTime? updatedAt,
  }) => ReadingProgress(
    locator: locator ?? this.locator,
    percent: percent ?? this.percent,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is ReadingProgress &&
      other.locator == locator &&
      other.percent == percent &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(locator, percent, updatedAt);

  @override
  String toString() => 'ReadingProgress($locator, $percent)';
}
