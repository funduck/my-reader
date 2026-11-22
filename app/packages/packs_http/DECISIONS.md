# Решения: packs_http

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/README.md](../../../docs/tasks/README.md#принятые-решения).

- `packs_http` (T-040): `HttpPackStore({baseUri, directory, client?, timeout})`. Файлы `<dir>/<id>.sqlite` и `<dir>/packs.json` (`{"packs": {id: version}}`). Ошибки — sealed `PackException`: `PackNetworkException`, `PackHashMismatchException`, `PackManifestException`, `PackNotFoundException`. Докачки и отмены нет.
