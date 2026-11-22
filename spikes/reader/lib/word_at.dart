import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

final _wordRe = RegExp(r"[A-Za-z]+(?:['’-][A-Za-z]+)*");

/// Word of [text] covering [offset], as [start, end), or null.
TextRange? wordRangeAt(String text, int offset) {
  for (final m in _wordRe.allMatches(text)) {
    if (offset >= m.start && offset < m.end) {
      return TextRange(start: m.start, end: m.end);
    }
  }
  return null;
}

/// Finds the [RenderEditable] that `SelectableText` builds under [context].
RenderEditable? findRenderEditable(BuildContext context) {
  RenderEditable? found;
  void visit(RenderObject o) {
    if (found != null) return;
    if (o is RenderEditable) {
      found = o;
      return;
    }
    o.visitChildren(visit);
  }

  final root = context.findRenderObject();
  if (root != null) visit(root);
  return found;
}

/// Character offset in the paragraph under a global point, or null.
int? charOffsetAt(BuildContext context, Offset globalPoint) {
  final editable = findRenderEditable(context);
  if (editable == null) return null;
  return editable.getPositionForPoint(globalPoint).offset;
}
