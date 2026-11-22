import 'dart:async';

/// Lets an action run at most once per [interval].
///
/// The first [poke] runs the action at once. Pokes during the cooldown are
/// merged into one run at the end of it. An action that returns `false` did
/// nothing, so it starts no cooldown.
class Throttle {
  /// Creates a throttle for [action].
  new({required this.interval, required this.action});

  /// Minimum time between two runs that did something.
  final Duration interval;

  /// The work; returns whether it did something.
  final bool Function() action;

  Timer? _cooldown;
  bool _pending = false;

  /// Asks for a run.
  void poke() {
    if (_cooldown != null) {
      _pending = true;
      return;
    }
    if (action()) _cooldown = Timer(interval, _cooledDown);
  }

  void _cooledDown() {
    _cooldown = null;
    if (!_pending) return;
    _pending = false;
    poke();
  }

  /// Cancels the cooldown and any pending run.
  void dispose() {
    _cooldown?.cancel();
    _cooldown = null;
    _pending = false;
  }
}
