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
build/      сборка пакетов: schema.py (DDL и нормализация), packdb.py (запись SQLite и manifest), fixtures.py, kaikki.py (дамп kaikki.org), pack_en_levels.py, pack_en_forms.py
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
- `zipf` — для всех лемм; `NULL`, если слова нет в wordfreq. Сверх CEFR добавляются топ-50 000 слов wordfreq (`pos = any`, `cefr = NULL`, `estimated = 0`). Оценка уровня по Zipf — отдельная задача (T-035).

## Пакет en-forms

Словоформа -> лемма из дампа kaikki.org (поле `forms` записей-лемм и значения `form-of` записей-форм) плюс Zipf из `wordfreq` для ранга. Сети не нужно, если дамп уже скачан.

```sh
uv run python -m build.pack_en_forms build                      # data/kaikki.org-dictionary-English.jsonl -> data/packs/en-forms-<версия дампа>.sqlite
uv run python -m build.pack_en_forms build --dump ПУТЬ.jsonl --out-dir ПАПКА --version ГГГГММДД[.N]
uv run python -m build.pack_en_forms info [ПУТЬ.sqlite]         # число строк, число форм, размер в байтах
```

Правила (подробности — в docstring `build/pack_en_forms.py`):

- Из `forms` берутся только формы со словоизменением (`plural`, `past`, `comparative`...) без тегов вариантов написания (`alternative`, `pronunciation-spelling`, `table-tags`...); многословные формы (`more left`) пропускаются. Архаичные и нестандартные формы (`goeth`, `goed`) остаются.
- Значение `form-of` даёт `форма -> лемма`; `"good and well"` разбивается на `good` и `well`, если обе части — заголовки.
- Строка `лемма -> лемма` только если у формы есть другие варианты. Ранг: сначала словоизменение (по убыванию Zipf леммы, затем алфавит), затем строки `лемма -> лемма`.
- Тесты работают на выборке `fixtures/kaikki/kaikki-forms.jsonl` (39 строк, атрибуция — как у `kaikki-100.jsonl`, см. `fixtures/kaikki/ATTRIBUTION.md`).
