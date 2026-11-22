/// Source of the current time, replaced by a fake in tests.
abstract interface class Clock {
  /// Returns the current moment.
  DateTime now();
}
