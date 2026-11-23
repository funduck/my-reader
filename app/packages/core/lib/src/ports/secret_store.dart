/// Key under which the DeepL API key is stored.
const String deeplApiKey = 'deepl_api_key';

/// Storage of secrets (API keys) in the secure storage of the OS.
///
/// Values never go to the profile, the database or the logs.
abstract interface class SecretStore {
  /// Returns the secret saved under [key], or `null` if there is none.
  Future<String?> read(String key);

  /// Saves [value] under [key]; `null` removes the secret.
  Future<void> write(String key, String? value);
}
