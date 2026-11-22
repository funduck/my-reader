# Архитектура сервиса

Общая схема «приложение + сервис» — в [Architecture.md](Architecture.md), источники данных — в [Data-sources.md](Data-sources.md).

## 1. MVP: сборка и раздача пакетов

В MVP сервис — это Python-скрипты и простой HTTP-сервер на Mac. Приложение на том же Mac скачивает пакеты с `localhost` и дальше работает офлайн. Когда появится Android, телефон будет качать их по Wi-Fi. Батчевая разметка глав (spaCy, идиомы) появится после MVP.

```
service/
  build/      скрипты сборки пакетов из открытых данных
  serve/      HTTP-раздача пакетов и manifest.json
  data/       скачанные дампы и собранные пакеты (не в git)
```

## 2. Пакеты

| Пакет | Источник | Содержимое |
|---|---|---|
| `en-en` | kaikki.org (Wiktionary) | Толкования, IPA, часть речи, примеры; индекс по лемме |
| `en-forms` | kaikki.org, поле `forms` | Словоформа → лемма |
| `en-levels` | CEFR-J, Octanove, wordfreq | `lemma \| pos \| cefr \| zipf \| estimated` |

Каждый пакет — один SQLite-файл. Сборка повторяемая: одна команда скачивает исходники нужной версии и собирает все пакеты.

## 3. Протокол

- `GET /manifest.json` — список пакетов: id, версия, размер, sha256, путь к файлу.
- `GET /packs/<id>-<version>.sqlite` — сам пакет.

Приложение сравнивает версии из манифеста со своими, качает новые, проверяет sha256 и подменяет файл целиком.

Адрес сервиса задаётся в настройках приложения, по умолчанию `http://localhost:8080`. Для Android после MVP: `serve --lan` и разрешение cleartext-трафика к частным адресам в Android-сборке.

## 4. Схемы пакетов

Это контракт между сервисом и приложением. Схему меняем только отдельной задачей: сначала версия `schema_version`, потом код сервиса и приложения. DDL ниже дословно совпадает с `service/build/schema.py`, это проверяет тест. Мини-пакеты по этим схемам лежат в `service/fixtures/`, их используют тесты приложения.

### 4.1. Общее для всех пакетов

- Один пакет — один файл SQLite. Приложение открывает его только на чтение (`package:sqlite3`). Все запросы ниже — параметризованные, `?` — параметр.
- Кодировка UTF-8, `PRAGMA user_version` = `schema_version` (сейчас `1`). Приложение читает пакет, только если `user_version` ему известна.
- Файлы пакетов в этой схеме не используют FTS5 и расширения SQLite. Поиск по префиксу — диапазоном по индексу: `key >= ? AND key < ?` (префикс и префикс с последним символом +1).
- Пустое значение — `NULL`, не пустая строка.

#### Таблица `meta`

Есть в каждом пакете.

```sql
CREATE TABLE meta (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;
```

Обязательные ключи:

| key | Значение | Пример |
|---|---|---|
| `pack_id` | Идентификатор пакета, совпадает с `id` в манифесте | `en-en` |
| `schema_version` | Версия схемы, строка с числом | `1` |
| `version` | Версия пакета, совпадает с манифестом | `20260101.1` |
| `source` | Откуда данные | `kaikki.org dump 2026-01-01` |
| `license` | Лицензия данных | `CC BY-SA 4.0` |

Билдер может добавлять другие ключи (например, `zipf_threshold`). Приложение их игнорирует.

#### Ключи поиска: нормализация

Колонки `key` (en-en), `form` и `lemma` (en-forms), `lemma` (en-levels) хранят **нормализованную** форму. Правила (функция `normalize_key` в `service/build/schema.py`), приложение применяет их к искомому слову перед запросом:

1. Типографские апострофы `’` `‘` `ʼ` `′` заменяются на `'`.
2. Нижний регистр (`toLowerCase()` в Dart).
3. Любая последовательность пробельных символов — один пробел, пробелы по краям убираются.

Дефисы, точки и другая пунктуация остаются: `mother-in-law`, `can't`, `take off`. Unicode-нормализация (NFC/NFD) не выполняется. Исходное написание (регистр) хранится отдельно в `entries.lemma`.

**Лемма** — основная форма слова в словаре: инфинитив глагола без `to` (`go`), единственное число существительного (`child`), положительная степень прилагательного (`good`). Лемма для всех пакетов записывается в нормализованном виде и совпадает с `entries.key` в `en-en`.

**Часть речи (`pos`)** — одно значение из закрытого списка, во всех пакетах одно и то же:

| `pos` | Что это |
|---|---|
| `noun`, `verb`, `adj`, `adv` | Существительное, глагол, прилагательное, наречие |
| `pron`, `prep`, `conj`, `intj`, `det`, `num`, `particle` | Местоимение, предлог, союз, междометие, определитель (включая артикли), числительное, частица |
| `name` | Имя собственное |
| `phrase` | Устойчивое выражение, фразовый глагол, идиома |
| `other` | Всё остальное (сокращения, приставки, символы) |

В `en-levels` дополнительно допустимо значение `any` — часть речи неизвестна. Приложение при необходимости приводит значения к своему enum, незнакомые значения трактует как `other`.

### 4.2. Пакет `en-en`

Толкования, IPA, часть речи и примеры. Русских переводов в пакете нет: EN→RU даёт StarDict. Источник — kaikki.org. Служебные значения (`form-of`, «plural of …») в пакет не входят, они уходят в `en-forms`.

```sql
CREATE TABLE entries (
  id INTEGER PRIMARY KEY,
  key TEXT NOT NULL,
  lemma TEXT NOT NULL,
  pos TEXT NOT NULL,
  ipa TEXT,
  rank INTEGER NOT NULL
);
CREATE INDEX entries_key ON entries (key, rank);

CREATE TABLE senses (
  id INTEGER PRIMARY KEY,
  entry_id INTEGER NOT NULL REFERENCES entries (id),
  idx INTEGER NOT NULL,
  gloss TEXT NOT NULL,
  tags TEXT
);
CREATE INDEX senses_entry ON senses (entry_id, idx);

CREATE TABLE examples (
  id INTEGER PRIMARY KEY,
  sense_id INTEGER NOT NULL REFERENCES senses (id),
  idx INTEGER NOT NULL,
  text TEXT NOT NULL
);
CREATE INDEX examples_sense ON examples (sense_id, idx);
```

| Таблица.колонка | Смысл |
|---|---|
| `entries` | Одна статья — одно слово и одна часть речи |
| `entries.key` | Нормализованная лемма. По нему ищет приложение. Одному ключу соответствует несколько статей: разные части речи (`go` verb, `go` noun) и разный регистр (`Polish` adj и `polish` verb имеют ключ `polish`) |
| `entries.lemma` | Написание из словаря, с регистром: `Paris`, `Polish` |
| `entries.pos` | Часть речи из списка в 4.1 |
| `entries.ipa` | Одна транскрипция с косыми чертами, `/ɡoʊ/`. `NULL`, если нет |
| `entries.rank` | Порядок среди статей с одним `key`, от 0. Меньше — важнее. Показывать статьи в порядке `rank` |
| `senses` | Значение статьи |
| `senses.idx` | Порядок значения внутри статьи, от 0 |
| `senses.gloss` | Толкование на английском, одна строка |
| `senses.tags` | `NULL` или JSON-массив строк: `["informal"]`, `["formal","literary"]` |
| `examples` | Пример употребления значения |
| `examples.idx` | Порядок примера внутри значения, от 0 |

Типовой запрос статьи:

```sql
SELECT id, lemma, pos, ipa FROM entries WHERE key = ? ORDER BY rank;
SELECT id, gloss, tags FROM senses WHERE entry_id = ? ORDER BY idx;
SELECT text FROM examples WHERE sense_id = ? ORDER BY idx;
```

Значение `senses.gloss` не содержит разметки. Если `entries.key` совпадает с нормализованной леммой из запроса, статья найдена; иначе приложение пробует нормализованную исходную форму (см. T-044).

### 4.3. Пакет `en-forms`

Словоформа → лемма. Источник — поле `forms` и значения `form-of` в дампе kaikki.org.

```sql
CREATE TABLE forms (
  form TEXT NOT NULL,
  lemma TEXT NOT NULL,
  pos TEXT NOT NULL,
  rank INTEGER NOT NULL,
  PRIMARY KEY (form, lemma, pos)
) WITHOUT ROWID;
CREATE INDEX forms_form ON forms (form, rank);
```

| Колонка | Смысл |
|---|---|
| `form` | Нормализованная словоформа: `went`, `children` |
| `lemma` | Нормализованная лемма: `go`, `child` |
| `pos` | Часть речи леммы |
| `rank` | Предпочтение среди вариантов одной формы, от 0. Меньше — лучше. Строит билдер: чаще встречающаяся лемма (Zipf) раньше, при равенстве — по алфавиту |

Правила:

- Неоднозначная форма имеет несколько строк: `left` → `leave` (verb, rank 0), `left` → `left` (adj, rank 1).
- Строка «лемма → сама лемма» нужна, только если у формы есть другие варианты (как `left` → `left` выше). Для обычного слова такой строки нет: если формы нет в таблице, приложение использует саму нормализованную форму как лемму.
- Приложение берёт `ORDER BY rank LIMIT 1`; если известна часть речи, сначала ищет строку с этим `pos`.

```sql
SELECT lemma, pos FROM forms WHERE form = ? ORDER BY rank;
```

### 4.4. Пакет `en-levels`

Уровни CEFR и частотность слов. Источник — CEFR-J, Octanove, wordfreq.

```sql
CREATE TABLE levels (
  lemma TEXT NOT NULL,
  pos TEXT NOT NULL,
  cefr TEXT CHECK (cefr IN ('a1', 'a2', 'b1', 'b2', 'c1', 'c2')),
  zipf REAL,
  estimated INTEGER NOT NULL DEFAULT 0 CHECK (estimated IN (0, 1)),
  PRIMARY KEY (lemma, pos)
) WITHOUT ROWID;
```

| Колонка | Смысл |
|---|---|
| `lemma` | Нормализованная лемма |
| `pos` | Часть речи из списка в 4.1 или `any`, если у записи её нет (слова из частотного списка вне CEFR) |
| `cefr` | `a1`, `a2`, `b1`, `b2`, `c1`, `c2` в нижнем регистре или `NULL`, если уровень неизвестен. Приложение отображает `NULL` в `CefrLevel.unknown` |
| `zipf` | Частотность по шкале Zipf (примерно от 0 до 8) или `NULL`, если слова нет в wordfreq |
| `estimated` | `0` — уровень взят из списка CEFR; `1` — оценён по `zipf` (показывать как приблизительный) |

Правила определения уровня в приложении (см. [Data-sources.md](Data-sources.md), раздел 4):

1. Лемма получена по `en-forms`.
2. Часть речи известна: строка с этой `pos`; нет — строка `any`; нет — как будто часть речи неизвестна.
3. Часть речи неизвестна: минимальный `cefr` среди строк леммы, где он не `NULL`.
4. Нет строк или везде `cefr IS NULL` — `unknown`. `zipf` и `estimated` берутся из выбранной строки (при минимуме — из строки с этим уровнем).

```sql
SELECT pos, cefr, zipf, estimated FROM levels WHERE lemma = ?;
```

### 4.5. `manifest.json`

Файл `GET /manifest.json`, UTF-8 JSON. Поля:

| Поле | Тип | Смысл |
|---|---|---|
| `manifest_version` | число | Версия формата манифеста, сейчас `1`. Приложение не читает манифест незнакомой версии |
| `generated_at` | строка | Время сборки, UTC, ISO 8601 (`2026-01-01T00:00:00Z`) |
| `packs` | массив | Пакеты, отсортированы по `id` |
| `packs[].id` | строка | `en-en`, `en-forms`, `en-levels` |
| `packs[].version` | строка | `YYYYMMDD` — дата дампа, необязательно `.N` — номер пересборки: `20260101`, `20260101.2`. Сравнивается как список чисел через точку (отсутствующая часть — `0`) |
| `packs[].schema_version` | число | Версия схемы пакета. Приложение пропускает пакет со схемой, которую не поддерживает |
| `packs[].size` | число | Размер файла в байтах |
| `packs[].sha256` | строка | SHA-256 содержимого файла, 64 символа hex, нижний регистр |
| `packs[].path` | строка | Путь файла относительно адреса сервиса, без ведущего `/`: `packs/<id>-<version>.sqlite` |
| `packs[].license` | строка | Лицензия данных, для экрана «Источники данных» |

Пример:

```json
{
  "manifest_version": 1,
  "generated_at": "2026-01-01T00:00:00Z",
  "packs": [
    {
      "id": "en-en",
      "version": "20260101.1",
      "schema_version": 1,
      "size": 40960,
      "sha256": "7d596faca20a508e1a0a94942db91587d05e9fb7acf410d4080e891bd8caab90",
      "path": "packs/en-en-20260101.1.sqlite",
      "license": "CC BY-SA 4.0"
    },
    {
      "id": "en-forms",
      "version": "20260101.1",
      "schema_version": 1,
      "size": 16384,
      "sha256": "7fada6ef1a200e59c937138f89828eb36027a5310447d8ffb0479754421a28c4",
      "path": "packs/en-forms-20260101.1.sqlite",
      "license": "CC BY-SA 4.0"
    },
    {
      "id": "en-levels",
      "version": "20260101.1",
      "schema_version": 1,
      "size": 12288,
      "sha256": "3acf90cfa39d4f96e623c4ff70b735edd1e207061cea4ed91793844f34bb1a23",
      "path": "packs/en-levels-20260101.1.sqlite",
      "license": "CC BY-SA 4.0"
    }
  ]
}
```

Приложение скачивает `<адрес сервиса>/<path>`, проверяет `size` и `sha256` и подменяет файл целиком. Установленная версия пакета хранится на стороне приложения (`packs.json`, см. T-040); внутри файла она также есть в `meta.version`.
