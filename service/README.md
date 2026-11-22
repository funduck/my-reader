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
build/      сборка пакетов: schema.py (DDL и нормализация), packdb.py (запись SQLite и manifest), fixtures.py, pack_en_levels.py
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
- `zipf` — для всех лемм; `NULL`, если слова нет в wordfreq. Сверх CEFR добавляются топ-50 000 слов wordfreq (`pos = any`, `cefr = NULL`, `estimated = 0`). Оценка уровня по Zipf — отдельная задача (T-035).
