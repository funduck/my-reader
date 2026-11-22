import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';

import 'change_feed.dart';

/// In-memory [ProfileRepository]; starts with the default profile.
class FakeProfileRepository implements ProfileRepository {
  /// Creates a repository holding [initial], by default `UserProfile()`.
  new([UserProfile? initial]) : _profile = initial ?? const UserProfile();

  UserProfile _profile;
  final ChangeFeed _feed = ChangeFeed();

  @override
  Future<UserProfile> get() async => _profile;

  @override
  Stream<UserProfile> watch() => _feed.watch(() => _profile);

  @override
  Future<void> save(UserProfile profile) async {
    _profile = profile;
    _feed.notify();
  }
}
