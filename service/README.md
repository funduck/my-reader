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
build/      сборка пакетов: schema.py (DDL и нормализация), packdb.py (запись SQLite и manifest), fixtures.py, kaikki.py (дамп kaikki.org), pack_en_levels.py
serve/      HTTP-раздача (появится в T-036)
data/       дампы и собранные пакеты, не в git
fixtures/   мини-пакеты для тестов приложения: manifest.json + packs/*.sqlite; cefr/ — выборки CSV для тестов en-levels
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

## Пакет en-levels

Уровни CEFR (CEFR-J A1–B2, Octanove C1–C2) и частотность Zipf из `wordfreq` (данные внутри пакета `wordfreq`, сеть не нужна).

```sh
uv run python -m build.pack_en_levels fetch   # CSV с GitHub -> data/cefr/ (нужна сеть до raw.githubusercontent.com)
uv run python -m build.pack_en_levels build   # data/cefr/ -> data/packs/en-levels-<дата>.sqlite
```

`build` принимает свои пути: `--cefrj ПУТЬ --octanove ПУТЬ --out-dir ПАПКА --version ГГГГММДД[.N] --extra-words 50000`.

Правила сведения (подробности — в docstring `build/pack_en_levels.py`):

- Заголовок со `/` (`color/colour`, `a.m./A.M./am/AM`) — отдельные леммы на каждый вариант, после нормализации дубли схлопываются.
- `pos` источников приводится к схеме: `adjective` -> `adj`, `modal auxiliary` и `be/do/have-verb` -> `verb`, `infinitive-to` -> `particle`, пустая -> `any`; опечатка `vern` -> `verb`.
- Одна пара (лемма, pos) в нескольких строках или в обоих списках — минимальный уровень.
- `zipf` — для всех лемм; `NULL`, если слова нет в wordfreq. Сверх CEFR добавляются топ-50 000 слов wordfreq (`pos = any`): уровень — оценка по порогам Zipf, `estimated = 1`; без Zipf — `cefr = NULL`. Слова из CEFR-списков — `estimated = 0`.

### Пороги Zipf -> CEFR

Пороги — константа `ZIPF_THRESHOLDS` в `build/zipf_thresholds.py`, описание метода и числа — в [../docs/Data-sources.md](../docs/Data-sources.md), раздел 4. Пересчёт и точность на отложенной выборке (зерно 35, 80/20):

```sh
uv run python -m build.pack_en_levels fit --examples 20 --cefrj data/cefr/cefrj-vocabulary-profile-1.5.csv --octanove data/cefr/octanove-vocabulary-profile-c1c2-1.0.csv
```

Команда печатает подобранные пороги, пороги из конфига и 20 примеров оценённых слов. Если подобранные пороги расходятся с конфигом (другие данные, другая версия wordfreq), обновите константу и таблицу в документации, затем пересоберите пакет (`build`).
