/// Source of unique ids, replaced by a deterministic one in tests.
abstract interface class IdGenerator {
  /// Returns a new id, unique among all ids this generator has returned.
  String newId();
}
