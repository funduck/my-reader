import 'package:material_ui/material_ui.dart';

final RegExp _token = RegExp('<[^>]*>|[^<]+|<');
final RegExp _tagName = RegExp(r'^<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)');
final RegExp _entity = RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

/// Whether [text] contains at least one HTML tag.
bool looksLikeHtml(String text) => RegExp('<[a-zA-Z/][^>]*>').hasMatch(text);

const _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

String _decode(String text) => text.replaceAllMapped(_entity, (m) {
  final name = m.group(1)!;
  if (name.startsWith('#')) {
    final hex = name.startsWith('#x');
    final code = int.tryParse(
      name.substring(hex ? 2 : 1),
      radix: hex ? 16 : 10,
    );
    if (code == null || code <= 0 || code > 0x10ffff) return m.group(0)!;
    return String.fromCharCode(code);
  }
  return _named[name] ?? m.group(0)!;
});

const _blocks = {
  'div', 'p', 'ol', 'ul', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', //
  'tr', 'blockquote',
};

/// Turns [html] into spans: `b`, `strong`, `i`, `em` and `br` are honoured;
/// block tags (`div`, `p`, `ol`, `ul`, `li`, `h1`-`h6`, `tr`, `blockquote`)
/// start a new line (empty lines are collapsed); `li` gets `1.` in `ol` and
/// `•` in `ul`, nested lists are indented by two spaces per level. Every
/// other tag is dropped and its text kept (the content of `script` and
/// `style` is dropped too). Entities are decoded.
List<InlineSpan> parseSimpleHtml(String html, {TextStyle? base}) {
  final spans = <InlineSpan>[];
  var bold = 0;
  var italic = 0;
  var skip = 0;
  // True at the start of a line and right after a list marker: a break there
  // would be empty, and leading spaces are dropped.
  var atLineStart = true;
  // One entry per open list: the number of the last `li`, or null for `ul`.
  final lists = <int?>[];

  void add(String text) {
    if (text.isEmpty) return;
    spans.add(
      TextSpan(
        text: text,
        style: (bold > 0 || italic > 0)
            ? TextStyle(
                fontWeight: bold > 0 ? FontWeight.bold : null,
                fontStyle: italic > 0 ? FontStyle.italic : null,
              )
            : null,
      ),
    );
    atLineStart = text.endsWith('\n');
  }

  void paragraphBreak() {
    if (atLineStart) return;
    // Spaces before a line break are noise.
    if (spans.isNotEmpty && spans.last is TextSpan) {
      final last = spans.last as TextSpan;
      final text = last.text ?? '';
      if (text.endsWith(' ')) {
        spans[spans.length - 1] = TextSpan(
          text: text.trimRight(),
          style: last.style,
        );
      }
    }
    add('\n');
  }

  void startItem() {
    paragraphBreak();
    final depth = lists.length;
    final number = depth > 0 ? lists.last : null;
    if (depth > 0 && number != null) lists[depth - 1] = number + 1;
    final marker = number == null ? '•' : '${number + 1}.';
    add('${'  ' * (depth > 1 ? depth - 1 : 0)}$marker ');
    atLineStart = true;
  }

  for (final match in _token.allMatches(html)) {
    final token = match.group(0)!;
    if (token.startsWith('<') && token.length > 1) {
      final tag = _tagName.firstMatch(token);
      if (tag == null) continue;
      final closing = tag.group(1) == '/';
      final name = tag.group(2)!.toLowerCase();
      final selfClosing = token.endsWith('/>');
      switch (name) {
        case 'script' || 'style':
          if (!selfClosing) skip += closing ? -1 : 1;
          if (skip < 0) skip = 0;
        case 'b' || 'strong':
          bold = closing ? (bold > 0 ? bold - 1 : 0) : bold + 1;
        case 'i' || 'em':
          italic = closing ? (italic > 0 ? italic - 1 : 0) : italic + 1;
        case 'br':
          if (skip == 0) paragraphBreak();
        case 'ol' || 'ul':
          if (skip == 0) {
            paragraphBreak();
            if (closing) {
              if (lists.isNotEmpty) lists.removeLast();
            } else if (!selfClosing) {
              lists.add(name == 'ol' ? 0 : null);
            }
          }
        case 'li' when !closing:
          if (skip == 0) startItem();
        case _ when _blocks.contains(name):
          if (skip == 0) paragraphBreak();
      }
    } else if (skip == 0) {
      // Line breaks of the source are not breaks in HTML.
      final text = _decode(token).replaceAll(RegExp(r'\s*\n\s*'), ' ');
      add(atLineStart ? text.trimLeft() : text);
    }
  }
  while (spans.isNotEmpty &&
      spans.last is TextSpan &&
      ((spans.last as TextSpan).text ?? '').trim().isEmpty) {
    spans.removeLast();
  }
  if (spans.isNotEmpty && spans.last is TextSpan) {
    final last = spans.last as TextSpan;
    spans[spans.length - 1] = TextSpan(
      text: (last.text ?? '').trimRight(),
      style: last.style,
    );
  }
  return spans;
}

/// Shows a small subset of HTML (`b`, `i`, `br`, blocks and lists) as rich
/// text.
class SimpleHtml extends StatelessWidget {
  /// Creates the widget for [html].
  const new(this.html, {this.prefix = '', this.style, super.key});

  /// Source markup.
  final String html;

  /// Plain text put before the markup, such as a sense number.
  final String prefix;

  /// Base style; defaults to the ambient body style.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: prefix),
          ...parseSimpleHtml(html),
        ],
      ),
    );
  }
}
