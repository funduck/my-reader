import 'package:core/ports.dart';

/// Abbreviations after which a period never ends a sentence (lower case,
/// without the final period).
const Set<String> _strongAbbreviations = {
  'mr',
  'mrs',
  'ms',
  'dr',
  'prof',
  'st',
  'jr',
  'sr',
  'mt',
  'vs',
  'cf',
  'e.g',
  'i.e',
};

/// Abbreviations that may also end a sentence: a period after them splits
/// only when the next sentence starts with an upper-case letter or digit.
const Set<String> _weakAbbreviations = {
  'etc',
  'u.s',
  'u.k',
  'a.m',
  'p.m',
  'inc',
  'ltd',
  'co',
};

final RegExp _nonAsciiLetter = RegExp(r'^\p{L}$', unicode: true);
final RegExp _nonAsciiDigit = RegExp(r'^\p{Nd}$', unicode: true);

bool _isLetter(int c) {
  if (c < 0x80) {
    return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  }
  return _nonAsciiLetter.hasMatch(String.fromCharCode(c));
}

bool _isDigit(int c) {
  if (c < 0x80) return c >= 0x30 && c <= 0x39;
  return _nonAsciiDigit.hasMatch(String.fromCharCode(c));
}

bool _isAlnum(int c) => _isLetter(c) || _isDigit(c);

bool _isLower(int c) {
  final s = String.fromCharCode(c);
  return s.toLowerCase() == s && s.toUpperCase() != s;
}

bool _isUpper(int c) {
  final s = String.fromCharCode(c);
  return s.toUpperCase() == s && s.toLowerCase() != s;
}

bool _isSpace(int c) =>
    c == 0x20 ||
    (c >= 0x09 && c <= 0x0D) ||
    c == 0xA0 ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x3000;

/// `.`, `!`, `?` and `…`.
bool _isTerminator(int c) => c == 0x2E || c == 0x21 || c == 0x3F || c == 0x2026;

/// Closing quotes and brackets that may follow a terminator.
bool _isCloser(int c) =>
    c == 0x22 || // "
    c == 0x27 || // '
    c == 0x201D || // right double quote
    c == 0x2019 || // right single quote
    c == 0xBB || // closing guillemet
    c == 0x29 || // )
    c == 0x5D; // ]

/// Opening quotes, brackets and dashes skipped when looking at the next
/// sentence start.
bool _isOpener(int c) =>
    c == 0x22 ||
    c == 0x27 ||
    c == 0x201C || // left double quote
    c == 0x2018 || // left single quote
    c == 0xAB || // opening guillemet
    c == 0x28 || // (
    c == 0x5B || // [
    c == 0x2014 || // em dash
    c == 0x2013; // en dash

bool _isApostrophe(int c) =>
    c == 0x27 || c == 0x2019 || c == 0x2B9 || c == 0x2BC;

bool _isHyphen(int c) => c == 0x2D || c == 0x2011;

/// English implementation of [TextAnalyzer].
///
/// Sentences end at `.`, `!`, `?`, `…` (with optional closing quotes or
/// brackets) followed by whitespace and a sentence start. There is no split
/// before a lower-case start, after a known abbreviation or initial, and
/// always a split at a blank line. Tokens are words containing a letter;
/// an apostrophe or hyphen between alphanumerics stays inside the token.
/// The lemma is, for now, the lower-cased word with `’` replaced by `'`.
final class EnglishTextAnalyzer implements TextAnalyzer {
  /// Creates the analyzer.
  const new();

  @override
  List<SentenceSpan> sentences(String text) {
    final result = <SentenceSpan>[];
    final n = text.length;
    var start = 0;

    void emit(int from, int to) {
      var s = from;
      var e = to;
      while (s < e && _isSpace(text.codeUnitAt(s))) {
        s++;
      }
      while (e > s && _isSpace(text.codeUnitAt(e - 1))) {
        e--;
      }
      if (s < e) result.add(SentenceSpan(s, e));
    }

    var i = 0;
    while (i < n) {
      final c = text.codeUnitAt(i);
      if (c == 0x0A || c == 0x0D) {
        final blankEnd = _blankLineEnd(text, i);
        if (blankEnd != null) {
          emit(start, i);
          start = blankEnd;
          i = blankEnd;
          continue;
        }
      }
      if (!_isTerminator(c)) {
        i++;
        continue;
      }
      var runEnd = i;
      while (runEnd < n && _isTerminator(text.codeUnitAt(runEnd))) {
        runEnd++;
      }
      var end = runEnd;
      while (end < n && _isCloser(text.codeUnitAt(end))) {
        end++;
      }
      if (end >= n) {
        i = n;
        break;
      }
      if (!_isSpace(text.codeUnitAt(end))) {
        i = end; // "3.5", "e.g.,", "U.S.A": not a boundary
        continue;
      }
      final single = runEnd - i == 1 && c == 0x2E;
      final next = _nextStart(text, end);
      final nextLower = next != null && _isLower(text.codeUnitAt(next));
      final nextUpperOrDigit =
          next != null &&
          (_isUpper(text.codeUnitAt(next)) || _isDigit(text.codeUnitAt(next)));
      var split = !nextLower;
      if (single && end == runEnd) {
        final abbr = _wordBefore(text, i);
        if (_strongAbbreviations.contains(abbr.toLowerCase()) ||
            _isInitial(abbr)) {
          split = false;
        } else if (_weakAbbreviations.contains(abbr.toLowerCase())) {
          split = nextUpperOrDigit;
        }
      }
      if (split) {
        emit(start, end);
        start = end;
      }
      i = end;
    }
    emit(start, n);
    return result;
  }

  /// If a blank line (two line breaks with only spaces between) starts at
  /// [i], returns the offset after all following whitespace; otherwise null.
  int? _blankLineEnd(String text, int i) {
    var breaks = 0;
    var j = i;
    while (j < text.length && _isSpace(text.codeUnitAt(j))) {
      if (text.codeUnitAt(j) == 0x0A) breaks++;
      j++;
    }
    return breaks >= 2 ? j : null;
  }

  /// Offset of the first character of the next sentence after [from],
  /// skipping whitespace and openers; null at the end of text.
  int? _nextStart(String text, int from) {
    var j = from;
    while (j < text.length &&
        (_isSpace(text.codeUnitAt(j)) || _isOpener(text.codeUnitAt(j)))) {
      j++;
    }
    return j < text.length ? j : null;
  }

  /// The run of letters and periods that ends right before the period at
  /// [period] (`e.g` for `e.g.`).
  String _wordBefore(String text, int period) {
    var j = period;
    while (j > 0) {
      final c = text.codeUnitAt(j - 1);
      if (_isLetter(c) || c == 0x2E) {
        j--;
      } else {
        break;
      }
    }
    return text.substring(j, period);
  }

  /// A single capital letter other than `I` (`J.` in `J. K. Rowling`).
  bool _isInitial(String word) {
    if (word.length != 1) return false;
    return _isUpper(word.codeUnitAt(0)) && word != 'I';
  }

  @override
  List<TextToken> tokens(String text) {
    final result = <TextToken>[];
    final n = text.length;
    var i = 0;
    while (i < n) {
      if (!_isAlnum(text.codeUnitAt(i))) {
        i++;
        continue;
      }
      final start = i;
      var hasLetter = false;
      while (i < n) {
        final c = text.codeUnitAt(i);
        if (_isAlnum(c)) {
          if (_isLetter(c)) hasLetter = true;
          i++;
        } else if (i + 1 < n && _joins(c, text.codeUnitAt(i + 1))) {
          i++;
        } else {
          break;
        }
      }
      if (hasLetter) result.add(TextToken(text.substring(start, i), start, i));
    }
    return result;
  }

  /// Whether [mid] between an alphanumeric and [after] stays in the token.
  bool _joins(int mid, int after) {
    if (_isApostrophe(mid)) return _isLetter(after);
    if (_isHyphen(mid)) return _isAlnum(after);
    return false;
  }

  @override
  String lemma(String word) =>
      word.toLowerCase().replaceAll('’', "'").replaceAll('ʼ', "'");
}
