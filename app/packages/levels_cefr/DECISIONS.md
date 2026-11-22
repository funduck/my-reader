# Решения: levels_cefr

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/README.md](../../../docs/tasks/README.md#принятые-решения).

- `levels_cefr` (T-050): `CefrLevelDictionary.open(PackStore)` (нет пакета — `empty()`, всегда `unknown`), `.fromPath(path)`, `close()`. Пакет проверяется один раз при `open`: после загрузки `en-levels` словарь открыть заново. С POS — строки с этим POS и `any`, иначе все; побеждает самый лёгкий известный уровень. Лемму приводит вызывающий.
