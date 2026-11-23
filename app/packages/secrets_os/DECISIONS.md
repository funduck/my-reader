# Решения: secrets_os

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/AGENT.md](../../../docs/tasks/AGENT.md#принятые-решения).

- `secrets_os` (T-092): `OsSecretStore({storage?})` — `SecretStore` над `flutter_secure_storage` (Keychain на macOS и iOS, Keystore на Android), параметры платформ по умолчанию. `write(key, null)` вызывает `delete`. Ошибка платформы пишется в лог `warning` (только имя ключа, не значение) и пробрасывается дальше. Тест — контрактный набор `secretStoreContract` на моке канала `plugins.it_nomads.com/flutter_secure_storage`.
- macOS: плагин по умолчанию использует data protection keychain, ему нужен entitlement `keychain-access-groups` в `DebugProfile.entitlements` и `Release.entitlements`. Запись в настоящую связку ключей проверяет человек (`flutter run -d macos`).
- Версия плагина: `flutter_secure_storage ^10` (10.3.4): Android-модуль на `compileSdk 36` и Java 17, macOS и iOS — `flutter_secure_storage_darwin`. 9.x тянул `compileSdk 34` и Java 8, а его `flutter_secure_storage_macos` снят с поддержки. 11.x пока нельзя: его windows-часть требует `win32 ^6`, а `file_picker ^10` — `win32 ^5`; поднимать вместе с `file_picker`.
