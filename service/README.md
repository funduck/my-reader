# service

Сборка и раздача пакетов данных для приложения. Архитектура и схемы пакетов — в [../docs/Architecture-service.md](../docs/Architecture-service.md), раздел «Схемы пакетов».

## Требования

- [uv](https://docs.astral.sh/uv/). Python 3.12 uv подтянет сам (версия записана в `.python-version`).

## Установка и проверки

```sh
cd service
uv sync                      # создаёт .venv и ставит pytest, ruff
uv run pytest                # тесты
uv run ruff check            # линтер
uv run ruff format --check   # формат (без --check — переформатировать)
```

## Структура

```
build/      сборка пакетов: schema.py (DDL и нормализация), packdb.py (запись SQLite и manifest), fixtures.py, kaikki.py (дамп kaikki.org)
serve/      HTTP-раздача (появится в T-036)
data/       дампы и собранные пакеты, не в git
fixtures/   мини-пакеты для тестов приложения: manifest.json + packs/*.sqlite
tests/
```

## Тестовые мини-пакеты

`fixtures/` собирается из данных, написанных вручную в `build/fixtures.py` (20–50 слов на пакет). После правки данных или схемы пересоберите и закоммитьте результат:

```sh
uv run python -m build.fixtures
```

Тесты проверяют, что файлы в `fixtures/` соответствуют схеме из документации, что `manifest.json` совпадает с файлами (размер, sha256) и что скрипт воспроизводит содержимое.

Папку `fixtures/` можно раздавать как корень сервиса (`python -m http.server -d fixtures 8080`): в ней есть `manifest.json` и `packs/`.

## Дамп kaikki.org

Источник для пакетов `en-en` и `en-forms` (T-032, T-033). Данные — Wiktionary, CC BY-SA 4.0.

```sh
uv run python -m build.kaikki fetch           # ≈3,4 ГБ в data/, с докачкой; версия — в data/*.jsonl.version
uv run python -m build.kaikki count           # потоковый проход по data/kaikki.org-dictionary-English.jsonl
uv run python -m build.kaikki count путь.jsonl --strict
```

`fetch` можно прерывать и запускать снова: недокачанное лежит в `*.part`, докачка идёт через HTTP Range (`If-Range` по `Last-Modified`). Версия дампа — дата `Last-Modified` сервера (`YYYYMMDD`), записывается в `kaikki.org-dictionary-English.jsonl.version` рядом с файлом. Если версия на сервере та же, повторный `fetch` ничего не качает.

Парсер (`build.kaikki.iter_entries` / `read_entries`) читает построчно и отдаёт датаклассы `Entry(word, pos, senses, sounds, forms)`. Плохие строки (не JSON, нет `word`/`pos`) пропускаются и считаются; `count --strict` возвращает код 1, если такие есть. Записи с `lang_code` не `en` пропускаются. Подробности — в докстринге модуля.

Тесты работают на фрагменте из 100 строк `fixtures/kaikki/kaikki-100.jsonl` (см. `ATTRIBUTION.md`) и на подменённом HTTP, без сети.
