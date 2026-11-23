import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'block_view.dart' show lookupHoldDuration;

/// Reports a single tap anywhere in [child] (T-087).
///
/// A gesture recognizer here would lose the arena to the `SelectableText`
/// inside, so the tap is read from raw pointer events. It is a tap when the
/// pointer is released before [lookupHoldDuration] without moving past
/// [kTouchSlop], no other pointer was down, the primary mouse button was
/// used, and no text had a selection when it went down. [onTap] is called
/// [kDoubleTapTimeout] after the release; a second tap in that time makes
/// both a double tap and nothing is reported.
///
/// A descendant opts out of a tap with [ViewTapDetector.ignore].
class ViewTapDetector extends StatefulWidget {
  /// Creates the detector around [child].
  const new({
    required this.onTap,
    required this.hasSelection,
    required this.child,
    super.key,
  });

  /// Called with the tap point in the coordinates of this widget and its
  /// size.
  final void Function(Offset position, Size size) onTap;

  /// Whether some text has a selection; a tap then only clears it.
  final bool Function() hasSelection;

  /// The tapped content.
  final Widget child;

  /// Makes the tap that starts with [pointer] not count; called from a
  /// pointer-down handler of a descendant (those run before this one).
  static void ignore(BuildContext context, int pointer) =>
      context.getInheritedWidgetOfExactType<_Scope>()?.state._ignored = pointer;

  @override
  State<ViewTapDetector> createState() => _ViewTapDetectorState();
}

class _Scope extends InheritedWidget {
  const new({required this.state, required super.child});

  final _ViewTapDetectorState state;

  @override
  bool updateShouldNotify(_Scope oldWidget) => false;
}

class _ViewTapDetectorState extends State<ViewTapDetector> {
  int? _ignored;
  final Set<int> _down = {};
  bool _valid = false;
  Offset? _start;
  Timer? _hold;
  Timer? _pending;
  Offset? _pendingAt;

  @override
  void dispose() {
    _hold?.cancel();
    _pending?.cancel();
    super.dispose();
  }

  void _fire(Offset at) {
    _pending = null;
    _pendingAt = null;
    if (!mounted) return;
    widget.onTap(at, (context.findRenderObject()! as RenderBox).size);
  }

  void _invalidate() {
    _valid = false;
    _hold?.cancel();
    _hold = null;
  }

  void _onDown(PointerDownEvent event) {
    _down.add(event.pointer);
    if (_down.length > 1) {
      _invalidate();
      return;
    }
    final pending = _pending;
    final pendingAt = _pendingAt;
    _valid = false;
    if (pending != null && pendingAt != null) {
      if ((event.localPosition - pendingAt).distance <= kDoubleTapSlop) {
        // The second tap of a double tap: neither is a view tap.
        pending.cancel();
        _pending = null;
        _pendingAt = null;
        return;
      }
      pending.cancel();
      _fire(pendingAt);
    }
    final ignored = _ignored == event.pointer;
    _ignored = null;
    if (!ignored && widget.hasSelection()) {
      // A tap outside the text does not clear a selection on touch by
      // itself; taking the focus away hides it.
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (ignored ||
        (event.kind == PointerDeviceKind.mouse &&
            event.buttons != kPrimaryButton)) {
      return;
    }
    _valid = true;
    _start = event.position;
    _hold = Timer(lookupHoldDuration, _invalidate);
  }

  void _onMove(PointerMoveEvent event) {
    final start = _start;
    if (!_valid || start == null) return;
    if ((event.position - start).distance > kTouchSlop) _invalidate();
  }

  void _onUp(PointerUpEvent event) {
    final wasValid = _valid;
    _down.remove(event.pointer);
    _hold?.cancel();
    _hold = null;
    _valid = false;
    if (!wasValid) return;
    final at = event.localPosition;
    _pendingAt = at;
    _pending = Timer(kDoubleTapTimeout, () => _fire(at));
  }

  void _onCancel(PointerCancelEvent event) {
    _down.remove(event.pointer);
    _invalidate();
  }

  @override
  Widget build(BuildContext context) => _Scope(
    state: this,
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.child,
    ),
  );
}
