"""Сборка пакета en-forms: словоформа -> лемма (+ часть речи) из дампа kaikki.org.

Запуск (из ``service/``)::

    uv run python -m build.pack_en_forms build [--dump ПУТЬ] [--out-dir ПАПКА] [--version ВЕРСИЯ]
    uv run python -m build.pack_en_forms info [ПУТЬ.sqlite]    # число строк и размер

Источник: дамп kaikki.org (Wiktionary, CC BY-SA 4.0), его читает ``build.kaikki``; Zipf — wordfreq.
Схема и правила — Architecture-service.md, раздел 4.3.

Два источника строк
-------------------

1. Поле ``forms`` записи-леммы: ``forms`` смешивает словоизменение (``plural``, ``past``,
   ``comparative``...) с вариантами написания и служебными строками. Форма берётся, если

   * хотя бы один её тег из ``INFLECTION_TAGS`` (словоизменение) и
   * ни одного тега из ``SPELLING_TAGS`` (``alternative``, ``pronunciation-spelling``,
     ``romanization``, ``table-tags``, ``inflection-template``...) и
   * форма — одно слово с хотя бы одной буквой (``further left``, ``-`` и ``no-table-tags``
     отбрасываются).

   Устаревшие и нестандартные формы (``archaic``, ``obsolete``, ``nonstandard``, ``dialectal``)
   остаются: читалка встречает ``goeth``, ``yode``, ``goed``. Запись-лемма — запись, у которой
   есть значение без тега ``form-of``/``alt-of``.
2. Значения ``form-of`` записи-формы: ``went`` (verb) ``form_of go`` -> ``went -> go``. Часть речи
   леммы берётся от записи-формы (для ``better`` adj -> ``good`` это adj). Значение вида
   ``"good and well"`` (одно значение ссылается на две леммы) разбивается по `` and ``, если целая
   строка не заголовок-лемма, а обе части — заголовки-леммы (``rock and roll`` остаётся целым).

Строка «лемма -> лемма»
-----------------------

Для формы, которая сама заголовок-лемма и у которой есть другие варианты, добавляются строки
``форма -> форма`` на каждую часть речи заголовка (``left -> left`` adj/adv/noun).
Для обычного слова такой строки нет.

Ранг
----

Внутри одной формы: сначала варианты из словоизменения, затем строки «лемма -> лемма»; внутри
группы — по убыванию Zipf леммы, затем по лемме и части речи (алфавит). Ранги сквозные, с нуля.
Отступление от формулировки в 4.3: чистый Zipf ставит ``left`` (5.62) выше ``leave`` (5.34),
а пример в документе требует ``left -> leave`` с рангом 0.
"""

from __future__ import annotations

import argparse
import datetime as dt
import sqlite3
import sys
from collections import defaultdict
from collections.abc import Callable, Iterable
from functools import cache
from pathlib import Path

from wordfreq import zipf_frequency

from build.kaikki import DATA_DIR, DUMP_NAME, Entry, ParseStats, read_entries, read_version
from build.packdb import FormRow, PackMeta, write_en_forms
from build.schema import POS_VALUES, normalize_key

SOURCE = "kaikki.org (Wiktionary), wordfreq"
LICENSE = "CC BY-SA 4.0"
DEFAULT_OUT_DIR = DATA_DIR / "packs"

#: Теги ``forms``, означающие словоизменение.
INFLECTION_TAGS = frozenset(
    {
        "plural",
        "singular",
        "past",
        "present",
        "future",
        "participle",
        "gerund",
        "infinitive",
        "imperative",
        "subjunctive",
        "indicative",
        "comparative",
        "superlative",
        "first-person",
        "second-person",
        "third-person",
    }
)

#: Теги вариантов написания и служебных строк: такая форма не попадает в пакет.
SPELLING_TAGS = frozenset(
    {
        "alternative",
        "pronunciation-spelling",
        "romanization",
        "table-tags",
        "inflection-template",
        "class",
        "misspelling",
    }
)

#: Теги значения, при которых оно не делает запись леммой.
NON_LEMMA_SENSE_TAGS = frozenset({"form-of", "alt-of"})

#: pos kaikki -> pos схемы. Остальное, чего нет в ``POS_VALUES``, — ``other``.
POS_MAP = {
    "article": "det",
    "proverb": "phrase",
    "prep_phrase": "phrase",
    "idiom": "phrase",
    "adv_phrase": "phrase",
    "verb_phrase": "phrase",
}

_SEPARATOR = " and "


def map_pos(pos: str) -> str:
    pos = POS_MAP.get(pos, pos)
    return pos if pos in POS_VALUES else "other"


def is_lemma_entry(entry: Entry) -> bool:
    """Есть ли у записи значение, не являющееся формой или вариантом другой записи."""
    return any(not NON_LEMMA_SENSE_TAGS.intersection(s.tags) for s in entry.senses)


def is_inflection(tags: tuple[str, ...]) -> bool:
    t = set(tags)
    return bool(t & INFLECTION_TAGS) and not t & SPELLING_TAGS


def _usable_form(form: str) -> bool:
    return " " not in form and any(c.isalpha() for c in form)


@cache
def zipf(word: str) -> float:
    """Zipf нормализованного слова (0.0, если wordfreq его не знает)."""
    return zipf_frequency(word, "en")


def build_rows(
    entries: Iterable[Entry],
    zipf_of: Callable[[str], float] = zipf,
) -> list[FormRow]:
    """Строки en-forms из потока записей дампа (память: заголовки-леммы и пары форма/лемма)."""
    headwords: dict[str, set[str]] = defaultdict(set)  # лемма -> pos схемы
    pairs: set[tuple[str, str, str]] = set()  # (форма, лемма, pos)
    composite: list[tuple[str, str, str]] = []  # (форма, "A and B", pos)

    for entry in entries:
        pos = map_pos(entry.pos)
        word = normalize_key(entry.word)
        if is_lemma_entry(entry):
            headwords[word].add(pos)
            for f in entry.forms:
                form = normalize_key(f.form)
                if is_inflection(f.tags) and _usable_form(form) and form != word:
                    pairs.add((form, word, pos))
        for sense in entry.senses:
            if "form-of" not in sense.tags:
                continue
            for target in sense.form_of:
                lemma = normalize_key(target)
                if not lemma or lemma == word:
                    continue
                if _SEPARATOR in lemma:
                    composite.append((word, lemma, pos))
                else:
                    pairs.add((word, lemma, pos))

    for form, lemma, pos in composite:
        parts = [p for p in lemma.split(_SEPARATOR) if p.strip()]
        if lemma not in headwords and len(parts) > 1 and all(p in headwords for p in parts):
            pairs.update((form, p, pos) for p in parts if p != form)
        else:
            pairs.add((form, lemma, pos))

    by_form: dict[str, list[tuple[str, str, bool]]] = defaultdict(list)
    for form, lemma, pos in pairs:
        by_form[form].append((lemma, pos, False))
    for form, variants in by_form.items():
        variants.extend((form, pos, True) for pos in headwords.get(form, ()))

    rows: list[FormRow] = []
    for form, variants in sorted(by_form.items()):
        ranked = sorted(variants, key=lambda v: (v[2], -zipf_of(v[0]), v[0], v[1]))
        rows.extend(FormRow(form, lemma, pos, rank) for rank, (lemma, pos, _) in enumerate(ranked))
    return rows


def build_pack(dump: Path, out_path: Path, version: str) -> list[FormRow]:
    """Читает дамп потоком и пишет ``en-forms`` в ``out_path``."""
    rows = build_rows(read_entries(dump, ParseStats()))
    write_en_forms(out_path, PackMeta("en-forms", version, SOURCE, LICENSE), rows)
    return rows


def pack_info(path: Path) -> str:
    """Строка для человека: число строк, форм и размер файла."""
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        n = con.execute("SELECT COUNT(*) FROM forms").fetchone()[0]
        distinct = con.execute("SELECT COUNT(DISTINCT form) FROM forms").fetchone()[0]
    finally:
        con.close()
    return f"{path}: {n} rows, {distinct} distinct forms, {path.stat().st_size} bytes"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="build.pack_en_forms")
    sub = parser.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="собрать en-forms из дампа kaikki.org")
    b.add_argument("--dump", type=Path, default=DATA_DIR / DUMP_NAME)
    b.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    b.add_argument("--version", help="ГГГГММДД[.N]; по умолчанию версия дампа, иначе сегодня")
    i = sub.add_parser("info", help="число строк и размер собранного пакета")
    i.add_argument("path", nargs="?", type=Path)
    args = parser.parse_args(argv)

    if args.cmd == "info":
        path = args.path
        if path is None:
            found = sorted(DEFAULT_OUT_DIR.glob("en-forms-*.sqlite"))
            if not found:
                print(f"нет пакета в {DEFAULT_OUT_DIR}", file=sys.stderr)
                return 1
            path = found[-1]
        print(pack_info(path))
        return 0

    version = args.version or read_version(args.dump) or dt.datetime.now(dt.UTC).strftime("%Y%m%d")
    out = args.out_dir / f"en-forms-{version}.sqlite"
    rows = build_pack(args.dump, out, version)
    print(f"{out}: {len(rows)} rows, {out.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
