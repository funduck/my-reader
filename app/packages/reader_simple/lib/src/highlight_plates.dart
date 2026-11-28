import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

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

  /// Height of the capitals as a share of the font size: the plate is
  /// centred halfway between the baseline and the top of the capitals. Most
  /// text fonts are close to 0.7.
  static const double capHeight = 0.7;
}

/// Height (ascent plus descent) and descent of a font without the line
/// height and its size, all in logical pixels.
typedef _FontMetrics = ({double height, double descent, double fontSize});

/// A piece of a block that gets a plate: `[start, end)` offsets in the text
/// of the block, the colour, and whether the plate pulses (`recent`, T-124).
typedef PlateRange = ({int start, int end, Color color, bool pulse});

/// One plate: its `rect` in the coordinates of `RenderHighlightPlates`, the
/// `color`, the `[start, end)` range it belongs to and the `opacity` it is
/// painted with now (1 unless the plate pulses); a range that runs over
/// several lines has a plate on each.
typedef Plate = ({Rect rect, Color color, int start, int end, double opacity});

/// The plates of [highlights] in [style]: where kinds overlap, the kind of
/// the highest priority wins; kinds without a background give none. The
/// plates of `recent` pulse.
List<PlateRange> plateRanges(
  List<BlockHighlight> highlights,
  ReaderStyle style,
) {
  if (highlights.isEmpty) return const [];
  return [
    for (final (:start, :end, :kind) in winningRanges(highlights))
      if (style.highlightOf(kind).background case final color?)
        (
          start: start,
          end: end,
          color: color,
          pulse: kind == HighlightKind.recent,
        ),
  ];
}

/// Paints rounded plates behind the text of its child, which must contain a
/// [RenderEditable] (a `SelectableText`).
///
/// The plates are painted under the child and take no room: the layout of
/// the text is the same with and without them. A plate is the box of the
/// range on one line, widened by [HighlightPlateShape]; a range on several
/// lines has a plate on each line, and neighbouring ranges have their own.
///
/// Plates with `pulse` are painted with the opacity of [pulse] (T-124) and
/// are not painted at all once it has completed; a change of [pulse] only
/// repaints, it never rebuilds or lays out. Without [pulse] they are painted
/// as the others.
class HighlightPlates extends SingleChildRenderObjectWidget {
  /// Draws [ranges], offsets in the text of [child].
  const new({
    required this.ranges,
    required super.child,
    this.pulse,
    super.key,
  });

  /// What to draw; equal lists draw the same.
  final List<PlateRange> ranges;

  /// The opacity of the plates that pulse; `null` — full.
  final Animation<double>? pulse;

  @override
  RenderHighlightPlates createRenderObject(BuildContext context) =>
      RenderHighlightPlates(ranges, pulse);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHighlightPlates renderObject,
  ) {
    renderObject
      ..ranges = ranges
      ..pulse = pulse;
  }
}

/// The render object of [HighlightPlates].
class RenderHighlightPlates extends RenderProxyBox {
  /// Draws [ranges] behind the child, the pulsing ones with [pulse].
  new(this._ranges, this._pulse);

  List<PlateRange> _ranges;
  Animation<double>? _pulse;

  /// What to draw.
  List<PlateRange> get ranges => _ranges;
  set ranges(List<PlateRange> value) {
    if (listEquals(value, _ranges)) return;
    _ranges = value;
    markNeedsPaint();
  }

  /// The opacity of the plates that pulse.
  Animation<double>? get pulse => _pulse;
  set pulse(Animation<double>? value) {
    if (identical(value, _pulse)) return;
    if (attached) _pulse?.removeListener(markNeedsPaint);
    _pulse = value;
    if (attached) value?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _pulse?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _pulse?.removeListener(markNeedsPaint);
    super.detach();
  }

  /// The plates as they are laid out now, in the coordinates of this
  /// object; empty before the first layout. The plates that pulse are left
  /// out once the pulse has completed.
  List<Plate> get plates {
    final editable = _findEditable(this);
    if (editable == null || !editable.hasSize || _ranges.isEmpty) {
      return const [];
    }
    final toThis = editable.getTransformTo(this);
    final pulse = _pulse;
    final result = <Plate>[];
    for (final (:start, :end, :color, pulse: pulses) in _ranges) {
      if (pulses && pulse != null && pulse.isCompleted) continue;
      final opacity = pulses && pulse != null ? pulse.value : 1.0;
      final lines = <Rect>[];
      final natural = _naturalHeight(editable, start);
      for (final box in editable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      )) {
        var rect = box.toRect();
        if (rect.isEmpty) continue;
        // The box reaches from the top of the font to the bottom of the
        // line, which grows with the line height: the plate would hang below
        // the letters. Centre it on the letters instead.
        if (natural != null) rect = _centred(rect, natural);
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
          opacity: opacity,
        ));
      }
    }
    return result;
  }

  /// A plate of the font's own height (ascent plus descent, without the
  /// line height) centred halfway between the baseline and the top of the
  /// capitals, so the space above and below the letters is the same.
  ///
  /// The bottom of [box] is the bottom of the line at any line height.
  /// The plate stays inside its line (`fontSize × lineHeight`, ending at
  /// the bottom of [box]), so plates of neighbouring lines never overlap.
  static Rect _centred(
    Rect box,
    ({_FontMetrics font, double lineHeight, TextLeadingDistribution leading})
    metrics,
  ) {
    final (:font, :lineHeight, leading: _) = metrics;
    final lineBottom = box.bottom;
    final lineTop = lineBottom - font.fontSize * lineHeight;
    final half = math.min(font.height, lineBottom - lineTop) / 2;
    final line = lineBottom - lineTop;
    final baseline = switch (metrics.leading) {
      // The extra height goes half above, half below the font.
      TextLeadingDistribution.even =>
        lineTop + (line - font.height) / 2 + font.height - font.descent,
      // The line is shared in the proportion of the ascent to the descent.
      TextLeadingDistribution.proportional =>
        lineBottom - line * font.descent / font.height,
    };
    final centre =
        (baseline - font.fontSize * HighlightPlateShape.capHeight / 2).clamp(
          lineTop + half,
          lineBottom - half,
        );
    return Rect.fromLTRB(box.left, centre - half, box.right, centre + half);
  }

  /// Metrics of the font at [offset] without the line height
  /// (`TextStyle.height`). `null` when the text has no style there or no
  /// line height is set: then the box already fits the letters.
  static ({
    _FontMetrics font,
    double lineHeight,
    TextLeadingDistribution leading,
  })?
  _naturalHeight(RenderEditable editable, int offset) {
    final text = editable.text;
    if (text == null) return null;
    final style = _styleAt(text, offset);
    if (style == null || style.height == null) return null;
    final probe = TextStyle(
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      fontFeatures: style.fontFeatures,
      fontVariations: style.fontVariations,
      locale: style.locale,
    );
    final lineHeight = style.height!;
    final leading =
        style.leadingDistribution ?? TextLeadingDistribution.proportional;
    final key = (probe, editable.textScaler);
    final cached = _naturalHeights[key];
    if (cached != null) {
      return (font: cached, lineHeight: lineHeight, leading: leading);
    }
    final painter = TextPainter(
      text: TextSpan(text: 'H', style: probe),
      textDirection: TextDirection.ltr,
      textScaler: editable.textScaler,
    )..layout();
    final line = painter.computeLineMetrics().first;
    final metrics = (
      height: line.ascent + line.descent,
      descent: line.descent,
      fontSize: editable.textScaler.scale(style.fontSize ?? 14),
    );
    painter.dispose();
    if (_naturalHeights.length >= 32) _naturalHeights.clear();
    _naturalHeights[key] = metrics;
    return (font: metrics, lineHeight: lineHeight, leading: leading);
  }

  static final _naturalHeights = <(TextStyle, TextScaler), _FontMetrics>{};

  /// The style of the text at [offset] in [root], merged down the tree.
  static TextStyle? _styleAt(InlineSpan root, int offset) {
    var position = 0;
    TextStyle? found;
    bool visit(InlineSpan span, TextStyle? inherited) {
      final style = inherited == null
          ? span.style
          : inherited.merge(span.style);
      if (span is! TextSpan) {
        position += 1;
        return true;
      }
      final length = span.text?.length ?? 0;
      if (offset >= position && offset < position + length) {
        found = style;
        return false;
      }
      position += length;
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (!visit(child, style)) return false;
      }
      return true;
    }

    visit(root, null);
    return found;
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
        if (plate.opacity <= 0) continue;
        context.canvas.drawRRect(
          RRect.fromRectAndRadius(
            plate.rect.shift(offset),
            const Radius.circular(HighlightPlateShape.radius),
          ),
          paint
            ..color = plate.opacity >= 1
                ? plate.color
                : plate.color.withValues(alpha: plate.color.a * plate.opacity),
        );
      }
    }
    super.paint(context, offset);
  }
}
