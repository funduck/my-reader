import 'package:meta/meta.dart';

import 'cefr_level.dart';
import 'ids.dart';
import 'term_status.dart';

/// Aggregate of a word or phrase, rebuildable from the journal.
@immutable
final class Term {
  /// Creates a term.
  const new({
    required this.id,
    required this.normalized,
    required this.language,
    required this.lookupCount,
    required this.eventIds,
    this.status = TermStatus.learning,
    this.level = CefrLevel.unknown,
  });

  /// Term id.
  final TermId id;

  /// Normalized form (lemma).
  final String normalized;

  /// Language code, for example `en`.
  final String language;

  /// How many times the term was looked up.
  final int lookupCount;

  /// Journal entries that mention the term, oldest first.
  final List<LookupEventId> eventIds;

  /// User's status for the term.
  final TermStatus status;

  /// CEFR level, [CefrLevel.unknown] if not known.
  final CefrLevel level;

  /// Copy with some fields replaced.
  Term copyWith({
    int? lookupCount,
    List<LookupEventId>? eventIds,
    TermStatus? status,
    CefrLevel? level,
  }) => Term(
    id: id,
    normalized: normalized,
    language: language,
    lookupCount: lookupCount ?? this.lookupCount,
    eventIds: eventIds ?? this.eventIds,
    status: status ?? this.status,
    level: level ?? this.level,
  );

  @override
  bool operator ==(Object other) {
    if (other is! Term ||
        other.id != id ||
        other.normalized != normalized ||
        other.language != language ||
        other.lookupCount != lookupCount ||
        other.status != status ||
        other.level != level ||
        other.eventIds.length != eventIds.length) {
      return false;
    }
    for (var i = 0; i < eventIds.length; i++) {
      if (other.eventIds[i] != eventIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    normalized,
    language,
    lookupCount,
    status,
    level,
    Object.hashAll(eventIds),
  );
}
