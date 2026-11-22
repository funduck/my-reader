/// Conversion of an EPUB chapter (XHTML) into a `ContentDocument`.
library;

import 'package:core/domain_books.dart';
import 'package:xml/xml.dart';

import '../epub_archive.dart' show parseXml;
import '../epub_path.dart';

/// A converted chapter: the document plus the places ids point to.
final class ChapterContent {
  /// Creates a converted chapter.
  const new({required this.document, required this.anchors});

  /// Blocks of the chapter.
  final ContentDocument document;

  /// Element `id` (and `<a name>`) to the index of the top-level block in
  /// [document] that holds the element. The first occurrence of an id wins.
  ///
  /// An id on an element that produces no block of its own (an empty
  /// `<div id="ch1"/>`, `<a id="x"/>`) points to the next block. An id after
  /// the last block is omitted.
  final Map<String, int> anchors;
}

/// Converts the XHTML text [xhtml] of the chapter stored at entry [path].
///
/// CSS and scripts are ignored. Supported: `p`, `h1`-`h6`, `blockquote`,
/// `ul`/`ol`/`li`, `img`, `br`, `em`/`i`, `strong`/`b`, `a`; other elements
/// are unwrapped into their text (block-like ones start a new paragraph).
/// Whitespace is collapsed the way a browser does it.
///
/// Links: an external `href` (any URL scheme) is kept as written; an internal
/// one is resolved against [path] to `<entry path>#<fragment>` (the fragment
/// is omitted when absent), so `#fn1` in `OEBPS/ch1.xhtml` becomes
/// `OEBPS/ch1.xhtml#fn1`. Image `src` is resolved against [path] to an entry
/// name; images that cannot be resolved (external, `data:`) are dropped.
///
/// Throws [FormatException] when [xhtml] is not well-formed XML.
ChapterContent convertXhtml(String xhtml, {required String path}) {
  final doc = parseXml(xhtml, path);
  return _Converter(path).convert(doc.rootElement);
}

const _skipped = {'head', 'script', 'style', 'template', 'svg', 'math'};

const _containers = {
  'html',
  'body',
  'div',
  'section',
  'article',
  'aside',
  'header',
  'footer',
  'main',
  'nav',
  'figure',
  'figcaption',
  'hgroup',
  'address',
  'details',
  'summary',
  'center',
  'pre',
  'dl',
  'dt',
  'dd',
  'li',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'td',
  'th',
  'caption',
  'form',
  'fieldset',
};

const _headings = {'h1': 1, 'h2': 2, 'h3': 3, 'h4': 4, 'h5': 5, 'h6': 6};

bool _isBlockTag(String name) =>
    name == 'p' ||
    name == 'blockquote' ||
    name == 'ul' ||
    name == 'ol' ||
    _headings.containsKey(name) ||
    _containers.contains(name);

final _spaces = RegExp(r'[ \t\r\n\f]+');
final _scheme = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:');

/// Mutable inline tree used while a run of inlines is being collected.
sealed class _Node {
  const new();
}

final class _Text extends _Node {
  new(this.text);
  String text;
}

enum _Kind { italic, bold, link }

final class _Wrap extends _Node {
  new(this.kind, this.href);
  final _Kind kind;
  final String? href;
  final List<_Node> children = [];

  bool get hasImage =>
      children.any((n) => n is _Image || (n is _Wrap && n.hasImage));
}

final class _Image extends _Node {
  const new(this.src, this.alt);
  final String src;
  final String? alt;
}

final class _Id extends _Node {
  const new(this.id);
  final String id;
}

/// Collects inlines of one paragraph-like element with browser whitespace.
final class _Run {
  final List<_Node> root = [];
  late List<_Node> _cur = root;

  /// Whether the next collapsible space must be dropped (start of line or
  /// right after a space).
  bool _noSpace = true;

  bool get isEmpty => _cur.isEmpty && root.isEmpty;

  void text(String raw) {
    var s = raw.replaceAll(_spaces, ' ');
    if (_noSpace && s.startsWith(' ')) s = s.substring(1);
    if (s.isEmpty) return;
    _cur.add(_Text(s));
    _noSpace = s.endsWith(' ');
  }

  void lineBreak() {
    _trim(root, trailing: ' ');
    _cur.add(_Text('\n'));
    _noSpace = true;
  }

  /// A break caused by a block element nested in inline context: only when
  /// the current line has content.
  void softBreak() {
    _trim(root, trailing: ' ');
    final last = _lastText(root);
    if (last != null && last.text != '\n') {
      _cur.add(_Text('\n'));
    }
    _noSpace = true;
  }

  void add(_Node node) => _cur.add(node);

  void open(_Wrap wrap) {
    _cur.add(wrap);
    _stack.add(_cur);
    _cur = wrap.children;
  }

  void close() => _cur = _stack.removeLast();

  final List<List<_Node>> _stack = [];
}

_Text? _lastText(List<_Node> nodes) {
  for (var i = nodes.length - 1; i >= 0; i--) {
    final n = nodes[i];
    if (n is _Text) return n;
    if (n is _Wrap) {
      final t = _lastText(n.children);
      if (t != null) return t;
    }
    if (n is _Image) return null;
  }
  return null;
}

/// Removes trailing [trailing] chars from the last text of [nodes] (skipping
/// id markers) and drops texts and wrappers that become empty.
/// Returns whether something non-empty remains at the end.
bool _trim(List<_Node> nodes, {required String trailing}) {
  for (var i = nodes.length - 1; i >= 0; i--) {
    final n = nodes[i];
    switch (n) {
      case _Id():
        continue;
      case _Image():
        return true;
      case _Text():
        while (n.text.isNotEmpty &&
            trailing.contains(n.text[n.text.length - 1])) {
          n.text = n.text.substring(0, n.text.length - 1);
        }
        if (n.text.isNotEmpty) return true;
        nodes.removeAt(i);
      case _Wrap():
        if (_trim(n.children, trailing: trailing)) return true;
        if (n.children.every((c) => c is _Id)) {
          // Keep the id markers of the dropped wrapper in place.
          nodes
            ..removeAt(i)
            ..insertAll(i, n.children);
        }
    }
  }
  return false;
}

void _trimLeadingSpace(List<_Node> nodes) {
  for (var i = 0; i < nodes.length;) {
    final n = nodes[i];
    switch (n) {
      case _Id():
        i++;
      case _Image():
        return;
      case _Text():
        n.text = n.text.replaceFirst(RegExp('^ +'), '');
        if (n.text.isNotEmpty) return;
        nodes.removeAt(i);
      case _Wrap():
        _trimLeadingSpace(n.children);
        if (n.children.any((c) => c is! _Id)) return;
        nodes
          ..removeAt(i)
          ..insertAll(i, n.children);
    }
  }
}

/// A piece of a run: inlines for one block, or an image between them.
List<Object> _split(List<_Node> nodes) {
  final result = <Object>[];
  var acc = <_Node>[];
  void flush() {
    if (acc.isNotEmpty) result.add(acc);
    acc = [];
  }

  for (final n in nodes) {
    if (n is _Image) {
      flush();
      result.add(n);
    } else if (n is _Wrap && n.hasImage) {
      for (final part in _split(n.children)) {
        if (part is List<_Node>) {
          acc.add(_Wrap(n.kind, n.href)..children.addAll(part));
        } else {
          flush();
          result.add(part);
        }
      }
    } else {
      acc.add(n);
    }
  }
  flush();
  return result;
}

/// Turns [nodes] into inlines, merging adjacent texts; ids go to [ids].
List<Inline> _freeze(List<_Node> nodes, List<String> ids) {
  final out = <Inline>[];
  void addInline(Inline inline) {
    final last = out.isEmpty ? null : out.last;
    if (inline is TextInline && last is TextInline) {
      out[out.length - 1] = TextInline(last.text + inline.text);
    } else {
      out.add(inline);
    }
  }

  for (final n in nodes) {
    switch (n) {
      case _Id(:final id):
        ids.add(id);
      case _Image():
        break;
      case _Text(:final text):
        if (text.isNotEmpty) addInline(TextInline(text));
      case _Wrap(:final kind, :final href):
        final children = _freeze(n.children, ids);
        if (children.isEmpty) continue;
        addInline(switch (kind) {
          _Kind.italic => ItalicInline(children),
          _Kind.bold => BoldInline(children),
          _Kind.link => LinkInline(href: href!, children: children),
        });
    }
  }
  return out;
}

final class _Converter {
  new(this.path);

  final String path;
  final List<Block> _root = [];
  final List<(String, Block)> _bound = [];
  final List<String> _waiting = [];

  ChapterContent convert(XmlElement rootElement) {
    final body = rootElement.name.local.toLowerCase() == 'html'
        ? rootElement.descendantElements.where(
            (e) => e.name.local.toLowerCase() == 'body',
          )
        : const <XmlElement>[];
    _blocks(body.isEmpty ? [rootElement] : [body.first], _root);

    final anchors = <String, int>{};
    for (final (id, block) in _bound) {
      final index = _root.indexWhere((top) => _contains(top, block));
      if (index >= 0) anchors.putIfAbsent(id, () => index);
    }
    return ChapterContent(
      document: ContentDocument(List.unmodifiable(_root)),
      anchors: Map.unmodifiable(anchors),
    );
  }

  bool _contains(Block top, Block target) =>
      identical(top, target) ||
      (top is QuoteBlock && top.blocks.any((b) => _contains(b, target)));

  void _emit(Block block, List<Block> sink) {
    sink.add(block);
    for (final id in _waiting) {
      _bound.add((id, block));
    }
    _waiting.clear();
  }

  void _noteId(XmlElement e) {
    final id = e.getAttribute('id');
    if (id != null && id.isNotEmpty) _waiting.add(id);
  }

  /// Block-level walk: loose inline content becomes anonymous paragraphs.
  void _blocks(Iterable<XmlNode> nodes, List<Block> sink) {
    var run = _Run();
    void flushRun() {
      _flush(run, sink, ParagraphBlock.new);
      run = _Run();
    }

    for (final node in nodes) {
      if (node is XmlElement) {
        final name = node.name.local.toLowerCase();
        if (_skipped.contains(name)) continue;
        if (_isBlockTag(name)) {
          flushRun();
          _block(node, name, sink);
        } else {
          _inline(node, name, run, allowImages: true);
        }
      } else if (node is XmlText || node is XmlCDATA) {
        run.text(node.value ?? '');
      }
    }
    flushRun();
  }

  void _block(XmlElement e, String name, List<Block> sink) {
    _noteId(e);
    final level = _headings[name];
    if (name == 'p') {
      final run = _Run();
      _inlineChildren(e, run, allowImages: true);
      _flush(run, sink, ParagraphBlock.new);
    } else if (level != null) {
      final run = _Run();
      _inlineChildren(e, run, allowImages: true);
      _flush(run, sink, (i) => HeadingBlock(level: level, inlines: i));
    } else if (name == 'blockquote') {
      final inner = <Block>[];
      _blocks(e.children, inner);
      if (inner.isNotEmpty) _emit(QuoteBlock(inner), sink);
    } else if (name == 'ul' || name == 'ol') {
      final items = <List<Inline>>[];
      final ids = <String>[];
      _listItems(e, items, ids);
      if (items.isNotEmpty) {
        _waiting.addAll(ids);
        _emit(ListBlock(ordered: name == 'ol', items: items), sink);
      }
    } else {
      _blocks(e.children, sink);
    }
  }

  void _listItems(XmlElement list, List<List<Inline>> items, List<String> ids) {
    for (final child in list.children) {
      if (child is! XmlElement) continue;
      final name = child.name.local.toLowerCase();
      if (name == 'li') {
        _item(child, items, ids);
      } else if (name == 'ul' || name == 'ol') {
        _listItems(child, items, ids);
      }
    }
  }

  void _item(XmlElement li, List<List<Inline>> items, List<String> ids) {
    final run = _Run();
    final id = li.getAttribute('id');
    if (id != null && id.isNotEmpty) run.add(_Id(id));
    final nested = <XmlElement>[];
    for (final child in li.children) {
      if (child is XmlElement) {
        final name = child.name.local.toLowerCase();
        if (name == 'ul' || name == 'ol') {
          nested.add(child);
          continue;
        }
        _inline(child, name, run, allowImages: false);
      } else if (child is XmlText || child is XmlCDATA) {
        run.text(child.value ?? '');
      }
    }
    final inlines = _finish(run.root, ids);
    if (inlines.isNotEmpty) items.add(inlines);
    for (final n in nested) {
      _listItems(n, items, ids);
    }
  }

  void _inlineChildren(XmlElement e, _Run run, {required bool allowImages}) {
    for (final child in e.children) {
      if (child is XmlElement) {
        _inline(
          child,
          child.name.local.toLowerCase(),
          run,
          allowImages: allowImages,
        );
      } else if (child is XmlText || child is XmlCDATA) {
        run.text(child.value ?? '');
      }
    }
  }

  void _inline(
    XmlElement e,
    String name,
    _Run run, {
    required bool allowImages,
  }) {
    if (_skipped.contains(name)) return;
    final id =
        e.getAttribute('id') ?? (name == 'a' ? e.getAttribute('name') : null);
    if (id != null && id.isNotEmpty) run.add(_Id(id));
    switch (name) {
      case 'br':
        run.lineBreak();
      case 'img':
        final src = e.getAttribute('src');
        final resolved = src == null ? null : resolveEntryPath(path, src);
        if (allowImages && resolved != null && resolved.isNotEmpty) {
          final alt = e.getAttribute('alt');
          run.add(_Image(resolved, alt == null || alt.isEmpty ? null : alt));
        }
      case 'em' || 'i':
        _wrapped(e, run, _Kind.italic, null, allowImages);
      case 'strong' || 'b':
        _wrapped(e, run, _Kind.bold, null, allowImages);
      case 'a':
        final href = e.getAttribute('href');
        if (href == null || href.trim().isEmpty) {
          _inlineChildren(e, run, allowImages: allowImages);
        } else {
          _wrapped(e, run, _Kind.link, _resolveHref(href.trim()), allowImages);
        }
      default:
        if (_isBlockTag(name)) {
          run.softBreak();
          _inlineChildren(e, run, allowImages: allowImages);
          run.softBreak();
        } else {
          _inlineChildren(e, run, allowImages: allowImages);
        }
    }
  }

  void _wrapped(
    XmlElement e,
    _Run run,
    _Kind kind,
    String? href,
    bool allowImages,
  ) {
    run.open(_Wrap(kind, href));
    _inlineChildren(e, run, allowImages: allowImages);
    run.close();
  }

  String _resolveHref(String href) {
    if (_scheme.hasMatch(href)) return href;
    final hash = href.indexOf('#');
    final fragment = hash < 0 ? null : href.substring(hash + 1);
    final target = hash == 0 ? path : resolveEntryPath(path, href);
    if (target == null) return href;
    return fragment == null || fragment.isEmpty ? target : '$target#$fragment';
  }

  /// Trims [nodes] and freezes them; ids found are added to [ids].
  List<Inline> _finish(List<_Node> nodes, List<String> ids) {
    _trim(nodes, trailing: ' \n');
    _trimLeadingSpace(nodes);
    return _freeze(nodes, ids);
  }

  /// Emits the run as blocks built with [wrap], images as `ImageBlock`s.
  void _flush(_Run run, List<Block> sink, Block Function(List<Inline>) wrap) {
    for (final part in _split(run.root)) {
      if (part is _Image) {
        _emit(ImageBlock(src: part.src, alt: part.alt), sink);
      } else {
        final ids = <String>[];
        final inlines = _finish(part as List<_Node>, ids);
        _waiting.addAll(ids);
        if (inlines.isNotEmpty) _emit(wrap(inlines), sink);
      }
    }
  }
}
