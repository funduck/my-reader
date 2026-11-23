# Решения: lookup_deepl

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/AGENT.md](../../../docs/tasks/AGENT.md#принятые-решения).

- `lookup_deepl` (T-091): `DeepLProvider({client, apiKey, timeout = 10 с})`, id `deepl` (`deepLProviderId`), только `enRu`, `isOnline: true`. `apiKey` — `Future<String?> Function()`, вызывается на каждый запрос; `null` или пустой — `ProviderUnavailable('no_key')` без обращения к сети. Ключ `…:fx` — `api-free.deepl.com`, иначе `api.deepl.com`; заголовок `Authorization: DeepL-Auth-Key <key>`. Тело — JSON `{text: [text], source_lang: EN, target_lang: RU, context?: sentence}`; `context` только если `sentence` не пустое. Результат — один `Sense(text)` без `partOfSpeech` и `transcription`.
- Ошибки: `ProviderUnavailable` с кодом в начале `message` — `no_key`, `network`, `timeout`, `bad_key` (403), `quota` (456), `rate_limit` (429), `server_error` (5xx), `http_<код>`, `bad_response`, `unsupported_mode`; пустой перевод — `LookupNotFound`. Ключ не попадает ни в лог, ни в `message`. Клиент `http.Client` принадлежит вызывающему, `close()` у провайдера нет.
- Отмена: `CancelToken` проверяется до запроса, после ключа и после ответа, а во время запроса — опросом раз в 20 мс; HTTP-запрос при этом не обрывается (`package:http` не умеет), ответ отбрасывается. Таймаут 10 с покрывает запрос вместе с телом ответа.
- Тесты — только `MockClient` из `package:http/testing.dart`, в настоящий DeepL не ходят.
