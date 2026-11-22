import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';

import 'change_feed.dart';

/// In-memory [TermRepository]; lists keep insertion order.
class FakeTermRepository implements TermRepository {
  /// Creates an empty repository.
  new();

  final Map<TermId, Term> _terms = {};
  final ChangeFeed _feed = ChangeFeed();

  @override
  Future<Term?> find(String normalized, String language) async {
    for (final term in _terms.values) {
      if (term.normalized == normalized && term.language == language) {
        return term;
      }
    }
    return null;
  }

  @override
  Stream<List<Term>> watchAll({TermStatus? status}) => _feed.watch(
    () => List.unmodifiable([
      for (final term in _terms.values)
        if (status == null || term.status == status) term,
    ]),
  );

  @override
  Future<void> save(Term term) async {
    _terms[term.id] = term;
    _feed.notify();
  }
}
