import 'package:meta/meta.dart';

import 'ids.dart';

/// One meaning: a translation or a definition.
@immutable
final class Sense {
  /// Creates a sense.
  const new({required this.text, this.partOfSpeech, this.examples = const []});

  /// Translation or definition text.
  final String text;

  /// Part of speech, if the provider gives it.
  final String? partOfSpeech;

  /// Usage examples, possibly empty.
  final List<String> examples;

  @override
  bool operator ==(Object other) =>
      other is Sense &&
      other.text == text &&
      other.partOfSpeech == partOfSpeech &&
      _listEquals(other.examples, examples);

  @override
  int get hashCode => Object.hash(text, partOfSpeech, Object.hashAll(examples));
}

/// A provider's answer.
@immutable
final class LookupResult {
  /// Creates a result.
  const new({required this.provider, required this.senses, this.transcription});

  /// Provider that produced the answer.
  final ProviderId provider;

  /// Meanings in provider order.
  final List<Sense> senses;

  /// IPA transcription, if known.
  final String? transcription;

  @override
  bool operator ==(Object other) =>
      other is LookupResult &&
      other.provider == provider &&
      other.transcription == transcription &&
      _listEquals(other.senses, senses);

  @override
  int get hashCode =>
      Object.hash(provider, transcription, Object.hashAll(senses));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
