# B-002. Техдолг: Android-сборка

**Статус:** backlog  
**Тип:** техдолг  
**Связано с:** [MVP-plan.md](../MVP-plan.md) (Android после MVP)

Всплыло при первой сборке `flutter build apk --release` (Flutter 3.50.1). Release-APK собирается и подписан debug-ключом.

## Пункты

1. **HTTP без TLS в release.** Сервис раздаёт пакеты по `http://` в локальной сети (`serve --lan`). Не проверено, пускает ли release-сборка такие запросы. Если в логе будет «Insecure HTTP is not allowed», нужен `network_security_config`: cleartext только для локальных адресов, а не `usesCleartextTraffic="true"` для всего.
2. **Размер APK.** Единый APK весит 63 МБ, потому что в нём библиотеки всех ABI. Для раздачи на телефон собирать с `--split-per-abi` (arm64 примерно втрое меньше) или AAB.
3. **Шрифт CupertinoIcons.** Сборка предупреждает: «Expected to find fonts for CupertinoIcons». В нашем коде `CupertinoIcons` и `cupertino_icons` нет, значит, иконку тянет зависимость. Найти, где она используется, и либо добавить `cupertino_icons`, либо заменить иконку. Иначе вместо неё будет пустой квадрат (вероятно, и на macOS).
4. **`file_picker` и Kotlin Gradle Plugin.** Предупреждение: будущие версии Flutter перестанут собирать плагины, которые сами подключают KGP. У нас `file_picker` 10.3.10, доступна 13.4.1. Обновить, когда в нём будет поддержка Built-in Kotlin, и проверить импорт книг на Android и macOS.
5. **Подпись release.** Сейчас release подписан debug-ключом (`android/app/build.gradle.kts`). Для раздачи вне своих устройств нужен свой keystore и `key.properties` (оба вне git).

6. **Телефон не видит сервис.** Причина не в приложении: сервис был запущен без `--lan` и слушал только `127.0.0.1`. Телефон (`192.168.0.10`) и Mac (`192.168.0.7`) в одной сети. Долг: в `service/README.md` и `app/README.md` нет сценария «телефон + Mac» (`serve --lan`, адрес Mac'а в настройках, файрвол macOS, `adb logcat`), а приложение показывает только «Service is not reachable» без подсказки.

## Результат

Задачи `T-…` на Android-платформу после MVP, по одной на пункт или одной пачкой.
