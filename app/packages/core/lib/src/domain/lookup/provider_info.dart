import 'package:meta/meta.dart';

import 'lookup_mode.dart';

/// Human-facing description of a lookup provider.
@immutable
final class ProviderInfo {
  /// Creates provider info.
  const new({required this.name, required this.isOnline, required this.modes});

  /// Display name.
  final String name;

  /// Whether the provider needs the network.
  final bool isOnline;

  /// Modes the provider supports.
  final Set<LookupMode> modes;

  @override
  bool operator ==(Object other) =>
      other is ProviderInfo &&
      other.name == name &&
      other.isOnline == isOnline &&
      other.modes.length == modes.length &&
      other.modes.containsAll(modes);

  @override
  int get hashCode =>
      Object.hash(name, isOnline, Object.hashAllUnordered(modes));
}
