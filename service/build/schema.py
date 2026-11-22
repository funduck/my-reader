"""Контракт пакетов данных: DDL SQLite, нормализация ключей, формат manifest.

Источник правды для людей — раздел «Схемы пакетов» в docs/Architecture-service.md.
Тесты проверяют, что DDL ниже слово в слово совпадает с документом.
"""

from __future__ import annotations

import re

#: Версия формата схем. Меняется только отдельной задачей вместе с приложением.
SCHEMA_VERSION = 1

#: Формат manifest.json.
MANIFEST_VERSION = 1

#: Допустимые значения колонки `pos` во всех пакетах.
POS_VALUES = (
    "noun",
    "verb",
    "adj",
    "adv",
    "pron",
    "prep",
    "conj",
    "intj",
    "det",
    "num",
    "particle",
    "name",
    "phrase",
    "other",
)

#: Значение `pos` в en-levels для записей без части речи.
POS_ANY = "any"

#: Допустимые уровни CEFR (нижний регистр, как в enum CefrLevel приложения).
CEFR_VALUES = ("a1", "a2", "b1", "b2", "c1", "c2")

DDL_META = """\
CREATE TABLE meta (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;"""

DDL_EN_EN = """\
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
CREATE INDEX examples_sense ON examples (sense_id, idx);"""

DDL_EN_FORMS = """\
CREATE TABLE forms (
  form TEXT NOT NULL,
  lemma TEXT NOT NULL,
  pos TEXT NOT NULL,
  rank INTEGER NOT NULL,
  PRIMARY KEY (form, lemma, pos)
) WITHOUT ROWID;
CREATE INDEX forms_form ON forms (form, rank);"""

DDL_EN_LEVELS = """\
CREATE TABLE levels (
  lemma TEXT NOT NULL,
  pos TEXT NOT NULL,
  cefr TEXT CHECK (cefr IN ('a1', 'a2', 'b1', 'b2', 'c1', 'c2')),
  zipf REAL,
  estimated INTEGER NOT NULL DEFAULT 0 CHECK (estimated IN (0, 1)),
  PRIMARY KEY (lemma, pos)
) WITHOUT ROWID;"""

#: Пакет -> DDL его таблиц (без `meta`, она общая).
PACK_DDL = {
    "en-en": DDL_EN_EN,
    "en-forms": DDL_EN_FORMS,
    "en-levels": DDL_EN_LEVELS,
}

#: Ключи таблицы `meta`, обязательные в каждом пакете.
META_KEYS = ("pack_id", "schema_version", "version", "source", "license")

#: Версия пакета: дата дампа и необязательный номер пересборки.
VERSION_RE = re.compile(r"^[0-9]{8}(\.[0-9]+)?$")

_APOSTROPHES = str.maketrans({"’": "'", "‘": "'", "ʼ": "'", "′": "'"})
_SPACES_RE = re.compile(r"\s+")


def normalize_key(text: str) -> str:
    """Нормализует слово для поиска в пакетах. Те же правила — в Dart.

    1. Типографские апострофы (U+2019, U+2018, U+02BC, U+2032) -> ``'``.
    2. Нижний регистр (``str.lower``, в Dart ``toLowerCase``).
    3. Любые пробельные последовательности -> один пробел, края обрезаются.

    Дефисы, точки и прочая пунктуация сохраняются. Unicode-нормализация (NFC) в ключах
    не выполняется: так результат одинаков в Python и Dart.
    """
    text = text.translate(_APOSTROPHES).lower()
    return _SPACES_RE.sub(" ", text).strip()
