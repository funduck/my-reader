/// Thrown by [CancelToken.throwIfCancelled] when work was cancelled.
class CancelledException implements Exception {
  /// Creates the exception.
  const new();

  @override
  String toString() => 'CancelledException';
}

/// Cooperative cancellation flag passed to long-running port calls.
///
/// The caller invokes [cancel]; the callee checks [isCancelled] between steps
/// and stops early, usually via [throwIfCancelled].
class CancelToken {
  bool _cancelled = false;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Marks the token cancelled. Calling it again has no effect.
  void cancel() => _cancelled = true;

  /// Throws [CancelledException] if the token is cancelled.
  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }
}
