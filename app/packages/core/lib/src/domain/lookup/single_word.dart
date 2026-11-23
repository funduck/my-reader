final RegExp _word = RegExp(
  r"^[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*$",
  unicode: true,
);

final RegExp _edge = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);

/// Whether [text] is one word.
///
/// A word is a run of Unicode letters and digits; an apostrophe (`'`, `’`) or
/// hyphen between two such runs keeps it one word ("don't", "well-known").
/// Whitespace and punctuation at the edges are ignored ("word.", "(word)").
/// Empty text and text with several words are not a single word.
bool isSingleWord(String text) => _word.hasMatch(text.replaceAll(_edge, ''));
