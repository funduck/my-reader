import 'package:core/ports.dart';

/// In-memory [SecretStore].
class FakeSecretStore implements SecretStore {
  /// Creates a store holding [initial] secrets.
  new([Map<String, String> initial = const {}]) : values = {...initial};

  /// Saved secrets by key, readable by tests.
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
