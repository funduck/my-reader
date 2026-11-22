import 'package:meta/meta.dart';

/// Exact text of a selection plus a little surrounding context, used to
/// restore a position independently of the renderer (W3C TextQuoteSelector).
@immutable
final class TextQuote {
  /// Creates a quote from already normalised parts.
  const new({required this.exact, this.prefix = '', this.suffix = ''});

  /// Restores a quote from [toJson] output.
  factory fromJson(Map<String, Object?> json) => TextQuote(
    exact: json['exact']! as String,
    prefix: json['prefix'] as String? ?? '',
    suffix: json['suffix'] as String? ?? '',
  );

  /// Builds a quote for `text.substring(start, end)`.
  ///
  /// The result holds the selection plus up to [contextLength] characters
  /// before and after it. Every run of whitespace (spaces, tabs, newlines)
  /// becomes one space. Context is cut after collapsing, so it is at most
  /// [contextLength] characters of the normalised text; the selection itself
  /// is collapsed but not trimmed or truncated. A cut never splits a
  /// surrogate pair.
  ///
  /// Throws [RangeError] unless `0 <= start < end <= text.length`: an empty
  /// or reversed range is not a selection, so no quote exists for it.
  factory fromText(String text, int start, int end) {
    RangeError.checkValidRange(start, end, text.length);
    if (start == end) {
      throw RangeError.value(end, 'end', 'must be greater than start');
    }
    final before = _collapse(text.substring(0, start));
    final after = _collapse(text.substring(end));
    return TextQuote(
      exact: _collapse(text.substring(start, end)),
      prefix: _tail(before, contextLength),
      suffix: _head(after, contextLength),
    );
  }

  /// Number of characters of context kept on each side.
  static const int contextLength = 30;

  /// The selected text, whitespace collapsed.
  final String exact;

  /// Up to [contextLength] characters immediately before [exact].
  final String prefix;

  /// Up to [contextLength] characters immediately after [exact].
  final String suffix;

  /// Returns a copy with the given fields replaced.
  TextQuote copyWith({String? exact, String? prefix, String? suffix}) =>
      TextQuote(
        exact: exact ?? this.exact,
        prefix: prefix ?? this.prefix,
        suffix: suffix ?? this.suffix,
      );

  /// JSON form for storage.
  Map<String, Object?> toJson() => {
    'exact': exact,
    'prefix': prefix,
    'suffix': suffix,
  };

  @override
  bool operator ==(Object other) =>
      other is TextQuote &&
      other.exact == exact &&
      other.prefix == prefix &&
      other.suffix == suffix;

  @override
  int get hashCode => Object.hash(exact, prefix, suffix);

  @override
  String toString() => 'TextQuote("$prefix[$exact]$suffix")';

  static final RegExp _whitespace = RegExp(r'\s+');

  static String _collapse(String s) => s.replaceAll(_whitespace, ' ');

  static String _tail(String s, int n) {
    if (s.length <= n) return s;
    var from = s.length - n;
    if (_isLowSurrogate(s.codeUnitAt(from))) from++;
    return s.substring(from);
  }

  static String _head(String s, int n) {
    if (s.length <= n) return s;
    var to = n;
    if (_isHighSurrogate(s.codeUnitAt(to - 1))) to--;
    return s.substring(0, to);
  }

  static bool _isHighSurrogate(int u) => u >= 0xD800 && u <= 0xDBFF;
  static bool _isLowSurrogate(int u) => u >= 0xDC00 && u <= 0xDFFF;
}
