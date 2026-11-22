import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';

import 'change_feed.dart';

/// In-memory [LookupJournal].
///
/// Filter semantics: an event belongs to the book and chapter of
/// `event.query.locator`; events without a locator never match a book or
/// chapter filter. [LookupFilter.from] is inclusive, [LookupFilter.to] is
/// exclusive. The level of an event is not stored in it, so the level filter
/// asks [levelOf] (by default every event is [CefrLevel.unknown]).
class FakeLookupJournal implements LookupJournal {
  /// Creates an empty journal.
  new({CefrLevel Function(LookupEvent event)? levelOf})
    : levelOf = levelOf ?? _unknownLevel;

  /// Tells the level of the term of an event, for [LookupFilter.level].
  final CefrLevel Function(LookupEvent event) levelOf;

  final List<LookupEvent> _events = [];
  final ChangeFeed _feed = ChangeFeed();

  static CefrLevel _unknownLevel(LookupEvent event) => CefrLevel.unknown;

  bool _matches(LookupEvent e, LookupFilter f) {
    final locator = e.query.locator;
    if (f.book != null && locator?.book != f.book) return false;
    if (f.chapter != null && locator?.chapter != f.chapter) return false;
    if (f.from != null && e.at.isBefore(f.from!)) return false;
    if (f.to != null && !e.at.isBefore(f.to!)) return false;
    if (f.level != null && levelOf(e) != f.level) return false;
    return true;
  }

  List<LookupEvent> _snapshot(LookupFilter filter) {
    // Newest first; among equal times the later record comes first.
    final list = [
      for (final e in _events.reversed)
        if (_matches(e, filter)) e,
    ]..sort((a, b) => b.at.compareTo(a.at));
    return List.unmodifiable(list);
  }

  @override
  Future<void> record(LookupEvent event) async {
    if (_events.any((e) => e.id == event.id)) {
      throw StateError('Duplicate lookup event id: ${event.id}');
    }
    _events.add(event);
    _feed.notify();
  }

  @override
  Future<LookupEvent?> get(LookupEventId id) async {
    for (final e in _events) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Stream<List<LookupEvent>> watch([
    LookupFilter filter = const LookupFilter(),
  ]) => _feed.watch(() => _snapshot(filter));
}
