import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// The opacity of the plate of a `recent` highlight at [t], the fraction
/// `[0, 1]` of `recentPulseDuration` that has passed (T-124).
///
/// Two pulses, then the fade to nothing: the plate rises to full at 10 %,
/// falls to 30 % at 35 %, rises again at 45 %, falls to 40 % at 70 % and
/// fades out. With [reduceMotion] there is no pulsing: full until 40 %, then
/// the fade, over the same time. The value is exactly 0 at `t >= 1`.
double recentPulseOpacity(double t, {required bool reduceMotion}) {
  final stops = reduceMotion ? _steadyStops : _pulseStops;
  if (t <= 0) return stops.first.$2;
  if (t >= 1) return 0;
  for (var i = 1; i < stops.length; i++) {
    final (to, toValue) = stops[i];
    if (t <= to) {
      final (from, fromValue) = stops[i - 1];
      return fromValue + (toValue - fromValue) * (t - from) / (to - from);
    }
  }
  return 0;
}

const List<(double, double)> _pulseStops = [
  (0, 0),
  (0.1, 1),
  (0.35, 0.3),
  (0.45, 1),
  (0.7, 0.4),
  (1, 0),
];

const List<(double, double)> _steadyStops = [(0, 1), (0.4, 1), (1, 0)];

/// The opacity of `recent` plates as an animation over [parent], which runs
/// `0 → 1` over `recentPulseDuration`.
///
/// One object serves a whole chapter, so the blocks that hold it need not be
/// rebuilt when the pulse starts or ends: only the plates listening to it
/// repaint. [reduceMotion] is set from `MediaQuery.disableAnimations`; it
/// takes effect on the next frame of a running pulse.
class RecentPulse extends Animation<double>
    with AnimationWithParentMixin<double> {
  /// The opacity over the progress of [parent].
  new(this.parent);

  @override
  final Animation<double> parent;

  /// Whether to fade without pulsing.
  bool reduceMotion = false;

  // A controller reports `completed` one frame after it reaches 1; the pulse
  // is over as soon as it does.
  @override
  AnimationStatus get status =>
      parent.value >= 1 ? AnimationStatus.completed : parent.status;

  @override
  double get value =>
      recentPulseOpacity(parent.value, reduceMotion: reduceMotion);

  @override
  String toString() => 'RecentPulse(${describeIdentity(this)}, $parent)';
}
