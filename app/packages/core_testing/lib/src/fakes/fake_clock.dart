import 'package:core/ports.dart';

/// A [Clock] that stands still until the test moves it.
class FakeClock implements Clock {
  /// Creates a clock showing [start], by default 2024-01-01 00:00 UTC.
  new([DateTime? start]) : time = start ?? DateTime.utc(2024);

  /// The moment the clock shows; assign to jump to another moment.
  DateTime time;

  @override
  DateTime now() => time;

  /// Moves the clock forward by [by].
  void advance(Duration by) => time = time.add(by);
}
