import 'package:core/ports.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('OsSecretStore');

/// [SecretStore] in the secure storage of the OS: Keychain on macOS and iOS,
/// Keystore on Android.
///
/// Values are never logged; only the key name and the failure are.
class OsSecretStore implements SecretStore {
  /// Creates the store over [storage], by default the platform storage.
  new({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Exception catch (e, s) {
      _log.warning('Cannot read the secret "$key"', e, s);
      rethrow;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } on Exception catch (e, s) {
      _log.warning('Cannot write the secret "$key"', e, s);
      rethrow;
    }
  }
}
