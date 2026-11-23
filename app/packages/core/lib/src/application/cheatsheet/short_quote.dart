import 'cheat_sheet_config.dart';

final RegExp _words = RegExp(r'\S+');

/// Cuts [sentence] to [window] words on each side of the first whole-word
/// occurrence of [word] (case-insensitive).
///
/// Each cut end gets an ellipsis. Returns the whole sentence when [word] is not
/// found or nothing needs cutting.
String shortQuote(
  String sentence,
  String word, {
  int window = shortQuoteWindow,
}) {
  if (word.isEmpty) return sentence;
  final target = RegExp(
    '(?<![\\p{L}\\p{N}])${RegExp.escape(word)}(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  final hit = target.firstMatch(sentence);
  if (hit == null) return sentence;
  final tokens = _words.allMatches(sentence).toList();
  final at = tokens.indexWhere((t) => t.end > hit.start);
  if (at < 0) return sentence;
  final first = at - window < 0 ? 0 : at - window;
  final last = at + window >= tokens.length ? tokens.length - 1 : at + window;
  final cutLeft = first > 0;
  final cutRight = last < tokens.length - 1;
  if (!cutLeft && !cutRight) return sentence;
  final body = sentence.substring(tokens[first].start, tokens[last].end);
  return '${cutLeft ? '… ' : ''}$body${cutRight ? ' …' : ''}';
}
