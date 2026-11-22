import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One typed field of a StarDict article.
@immutable
class StarDictField {
  /// Creates a field of [type] with [text].
  const new(this.type, this.text);

  /// StarDict type letter: `m` plain text, `h` HTML, `x` XDXF, and so on.
  final String type;

  /// Field content. For `x` the tags are already stripped; `h` is raw HTML.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is StarDictField && other.type == type && other.text == text;

  @override
  int get hashCode => Object.hash(type, text);

  @override
  String toString() => 'StarDictField($type, $text)';
}

/// An article from `.dict`, split into typed fields.
@immutable
class StarDictArticle {
  /// Creates an article from [fields].
  const new(this.fields);

  /// Splits the raw [bytes] of one article into fields.
  ///
  /// With [sameTypeSequence] (the `.ifo` value, e.g. `m` or `tm`) the types
  /// come from it, and the last field has no terminator or size prefix. With
  /// null every field starts with its type byte. Lowercase types are text
  /// ending with NUL (a missing final NUL is tolerated); uppercase types are
  /// binary with a 4-byte big-endian size prefix and are skipped, since the
  /// modal shows text only. Throws [FormatException] on a truncated field.
  factory parse(Uint8List bytes, String? sameTypeSequence) {
    final fields = <StarDictField>[];
    final seq = sameTypeSequence;
    var pos = 0;
    var index = 0;
    while (pos < bytes.length && (seq == null || index < seq.length)) {
      final String type;
      if (seq == null) {
        type = String.fromCharCode(bytes[pos++]);
      } else {
        type = seq[index];
      }
      index++;
      final isLast = seq != null && index == seq.length;
      if (_isBinary(type)) {
        pos = _skipBinary(bytes, pos, isLast);
        continue;
      }
      final int end;
      final int next;
      if (isLast) {
        end = bytes.length;
        next = end;
      } else {
        final nul = bytes.indexOf(0, pos);
        end = nul < 0 ? bytes.length : nul;
        next = nul < 0 ? bytes.length : nul + 1;
      }
      final text = utf8.decode(bytes.sublist(pos, end), allowMalformed: true);
      fields.add(StarDictField(type, type == 'x' ? stripXdxf(text) : text));
      pos = next;
    }
    return StarDictArticle(fields);
  }

  /// Fields in article order (text fields only).
  final List<StarDictField> fields;

  /// All field texts joined with a newline.
  String get text => fields.map((f) => f.text).join('\n');

  static bool _isBinary(String type) {
    final c = type.codeUnitAt(0);
    return c >= 0x41 && c <= 0x5A;
  }

  static int _skipBinary(Uint8List bytes, int pos, bool isLast) {
    if (isLast) return bytes.length;
    if (pos + 4 > bytes.length) {
      throw FormatException('Truncated binary field size', pos);
    }
    final size = ByteData.sublistView(bytes).getUint32(pos);
    final end = pos + 4 + size;
    if (end > bytes.length) {
      throw FormatException('Truncated binary field', pos);
    }
    return end;
  }

  @override
  bool operator ==(Object other) =>
      other is StarDictArticle && _sameFields(other.fields, fields);

  @override
  int get hashCode => Object.hashAll(fields);

  @override
  String toString() => 'StarDictArticle($fields)';
}

bool _sameFields(List<StarDictField> a, List<StarDictField> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Turns XDXF into plain text: drops tags, decodes the five XML entities.
String stripXdxf(String xdxf) => xdxf
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&')
    .trim();
