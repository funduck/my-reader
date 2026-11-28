import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'highlights.dart';
import 'reader_style.dart';

/// The shape of the plates behind highlighted text (T-123).
///
/// The values are a first guess, to be tuned by eye (U-10).
abstract final class HighlightPlateShape {
  /// Radius of the corners.
  static const double radius = 4;

  /// How far a plate reaches past the letters on the left and the right.
  static const double horizontalPadding = 2;

  /// How far a plate reaches past the text box above and below; negative
  /// pulls it in.
  ///
  /// The box of a line is as tall as the line (`fontSize × lineHeight`), so
  /// the boxes of two lines touch at any line height; pulling each plate in
  /// by 1 px leaves a 2 px gap between plates of neighbouring lines, so they
  /// never overlap.
  static const double verticalPadding = -1;
}

/// A piece of a block that gets a plate: `[start, end)` offsets in the text
/// of the block and the colour.
typedef PlateRange = ({int start, int end, Color color});

/// One plate: its `rect` in the coordinates of `RenderHighlightPlates`, the
/// `color` and the `[start, end)` range it belongs to; a range that runs
/// over several lines has a plate on each.
typedef Plate = ({Rect rect, Color color, int start, int end});

/// The plates of [highlights] in [style]: where kinds overlap, the kind of
/// the highest priority wins; kinds without a background give none.
List<PlateRange> plateRanges(
  List<BlockHighlight> highlights,
  ReaderStyle style,
) {
  if (highlights.isEmpty) return const [];
  return [
    for (final (:start, :end, :kind) in winningRanges(highlights))
      if (style.highlightOf(kind).background case final color?)
        (start: start, end: end, color: color),
  ];
}

/// Paints rounded plates behind the text of its child, which must contain a
/// [RenderEditable] (a `SelectableText`).
///
/// The plates are painted under the child and take no room: the layout of
/// the text is the same with and without them. A plate is the box of the
/// range on one line, widened by [HighlightPlateShape]; a range on several
/// lines has a plate on each line, and neighbouring ranges have their own.
class HighlightPlates extends SingleChildRenderObjectWidget {
  /// Draws [ranges], offsets in the text of [child].
  const new({required this.ranges, required super.child, super.key});

  /// What to draw; equal lists draw the same.
  final List<PlateRange> ranges;

  @override
  RenderHighlightPlates createRenderObject(BuildContext context) =>
      RenderHighlightPlates(ranges);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHighlightPlates renderObject,
  ) {
    renderObject.ranges = ranges;
  }
}

/// The render object of [HighlightPlates].
class RenderHighlightPlates extends RenderProxyBox {
  /// Draws [ranges] behind the child.
  new(this._ranges);

  List<PlateRange> _ranges;

  /// What to draw.
  List<PlateRange> get ranges => _ranges;
  set ranges(List<PlateRange> value) {
    if (listEquals(value, _ranges)) return;
    _ranges = value;
    markNeedsPaint();
  }

  /// The plates as they are laid out now, in the coordinates of this
  /// object; empty before the first layout.
  List<Plate> get plates {
    final editable = _findEditable(this);
    if (editable == null || !editable.hasSize || _ranges.isEmpty) {
      return const [];
    }
    final toThis = editable.getTransformTo(this);
    final result = <Plate>[];
    for (final (:start, :end, :color) in _ranges) {
      final lines = <Rect>[];
      for (final box in editable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      )) {
        final rect = box.toRect();
        if (rect.isEmpty) continue;
        // Boxes of one line (runs of other fonts, directions) are one plate.
        final i = lines.indexWhere((line) => _sameLine(line, rect));
        if (i < 0) {
          lines.add(rect);
        } else {
          lines[i] = lines[i].expandToInclude(rect);
        }
      }
      for (final line in lines) {
        result.add((
          rect: _widen(MatrixUtils.transformRect(toThis, line)),
          color: color,
          start: start,
          end: end,
        ));
      }
    }
    return result;
  }

  static RenderEditable? _findEditable(RenderObject root) {
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
      } else {
        child.visitChildren(visit);
      }
    }

    root.visitChildren(visit);
    return found;
  }

  static bool _sameLine(Rect a, Rect b) {
    final overlap =
        (a.bottom < b.bottom ? a.bottom : b.bottom) -
        (a.top > b.top ? a.top : b.top);
    final smaller = a.height < b.height ? a.height : b.height;
    return overlap > smaller / 2;
  }

  static Rect _widen(Rect box) {
    const horizontal = HighlightPlateShape.horizontalPadding;
    // Never turn a very low box inside out.
    final vertical = HighlightPlateShape.verticalPadding.clamp(
      -box.height / 4,
      double.infinity,
    );
    return Rect.fromLTRB(
      box.left - horizontal,
      box.top - vertical,
      box.right + horizontal,
      box.bottom + vertical,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_ranges.isNotEmpty) {
      final paint = Paint();
      for (final plate in plates) {
        context.canvas.drawRRect(
          RRect.fromRectAndRadius(
            plate.rect.shift(offset),
            const Radius.circular(HighlightPlateShape.radius),
          ),
          paint..color = plate.color,
        );
      }
    }
    super.paint(context, offset);
  }
}
