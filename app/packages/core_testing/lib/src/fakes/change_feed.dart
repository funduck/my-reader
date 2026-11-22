import 'dart:async';

/// Helper for fakes: builds watch streams that emit the current value on
/// listen and again after every [notify].
class ChangeFeed {
  /// Creates a feed with no listeners.
  new();

  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  /// Tells all listeners that the data changed.
  void notify() => _changes.add(null);

  /// Returns a stream of `snapshot()` values: first on listen, then per change.
  Stream<T> watch<T>(T Function() snapshot) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<T>(
      onListen: () {
        controller.add(snapshot());
        sub = _changes.stream.listen((_) => controller.add(snapshot()));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }
}
