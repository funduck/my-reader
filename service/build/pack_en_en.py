"""Сборка пакета en-en (толкования, IPA, часть речи, примеры) из дампа kaikki.org.

Запуск (из ``service/``)::

    uv run python -m build.pack_en_en build [--dump ПУТЬ] [--out-dir ПАПКА] [--min-zipf X]
    uv run python -m build.pack_en_en report [--pack ПУТЬ]

Источник — ``build.kaikki.read_entries``. Версия пакета — версия дампа
(``kaikki.read_version``), формат ``YYYYMMDD``. Данные Wiktionary — CC BY-SA 4.0.

Правила отбора и сведения:

* **Служебные значения** — тег ``form-of`` или непустой ``form_of`` («plural of pie») — в пакет
  не входят: они уходят в en-forms (T-033).
* **``alt-of``** («Alternative form of X», «Abbreviation of X», «Initialism of X») остаётся:
  читателю, нажавшему на ``GDP`` или ``encyclopaedia``, это единственное объяснение; тег идёт
  в ``senses.tags``. Значение без толкования выбрасывается.
* **Статья без значений** после фильтра (например ``pies``, где всё form-of) в пакет не попадает.
* **Толкование** — последний элемент ``glosses``: kaikki кладёт в ``glosses`` цепочку
  «рубрика -> родительское значение -> значение», нужное — последнее. Пробелы схлопываются.
* **Примеры** — не больше ``MAX_EXAMPLES`` на значение (размер пакета), в порядке дампа.
* **IPA** — первая транскрипция в косых чертах ``/…/`` (фонемная; ``[…]`` — фонетическая, не
  берём); ``NULL``, если такой нет.
* **pos** — ``POS_MAP``: kaikki -> закрытый список схемы; неизвестное -> ``other``.
* **rank** — порядок среди статей с одним ``key``: сначала статьи, у которых ``lemma == key``
  (``polish`` перед ``Polish``), затем порядок дампа (порядок статьи на странице Wiktionary).

Размер. Сначала пакет собирается целиком. Если он больше ``SIZE_LIMIT_BYTES`` (150 МБ) и порог
не задан, сборка автоматически повторяется с ``DEFAULT_CUT_ZIPF``: статьи, у которых
``wordfreq.zipf_frequency(key) < порога`` (слова, которых wordfreq не знает, получают 0.0),
отбрасываются. Явный ``--min-zipf X`` применяется сразу; ``--min-zipf 0`` — без отсечения даже
при большом размере. Порог пишется в ``meta.zipf_threshold``.
"""

from __future__ import annotations

import argparse
import re
import sqlite3
import sys
from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from pathlib import Path

from wordfreq import zipf_frequency

from build import kaikki
from build.packdb import EntryRow, PackMeta, SenseRow, write_en_en
from build.schema import normalize_key

PACK_ID = "en-en"
LICENSE = "CC BY-SA 4.0"
DEFAULT_DUMP = kaikki.DATA_DIR / kaikki.DUMP_NAME
DEFAULT_OUT_DIR = kaikki.DATA_DIR / "packs"

#: Если пакет больше, сборка повторяется с порогом ``DEFAULT_CUT_ZIPF`` (требование T-032).
SIZE_LIMIT_BYTES = 150 * 1024 * 1024
#: Порог Zipf для автоматического отсечения. Оценка, на реальном дампе не проверялась.
DEFAULT_CUT_ZIPF = 2.0
#: Сколько примеров оставлять у значения.
MAX_EXAMPLES = 3

#: Часть речи kaikki -> `pos` схемы; чего здесь нет — ``other``.
POS_MAP = {
    "noun": "noun",
    "verb": "verb",
    "adj": "adj",
    "adv": "adv",
    "pron": "pron",
    "prep": "prep",
    "postp": "prep",
    "conj": "conj",
    "intj": "intj",
    "det": "det",
    "article": "det",
    "num": "num",
    "particle": "particle",
    "name": "name",
    "phrase": "phrase",
    "prep_phrase": "phrase",
    "proverb": "phrase",
}

_SPACES = re.compile(r"\s+")
_IPA_PHONEMIC = re.compile(r"^/.+/$")


@dataclass(slots=True)
class BuildStats:
    """Счётчики сборки: что прочитано и что отброшено."""

    read: int = 0
    kept: int = 0
    no_senses: int = 0
    cut_by_zipf: int = 0
    dropped_senses: int = 0


def map_pos(pos: str) -> str:
    return POS_MAP.get(pos, "other")


def is_service_sense(sense: kaikki.Sense) -> bool:
    """Значение вида «plural of pie» — уходит в en-forms."""
    return "form-of" in sense.tags or bool(sense.form_of)


def pick_ipa(sounds: Iterable[kaikki.Sound]) -> str | None:
    for sound in sounds:
        if _IPA_PHONEMIC.match(sound.ipa):
            return sound.ipa
    return None


def convert_entry(entry: kaikki.Entry, stats: BuildStats | None = None) -> EntryRow | None:
    """Строка пакета из записи дампа; ``None``, если полезных значений не осталось."""
    senses: list[SenseRow] = []
    for sense in entry.senses:
        gloss = _SPACES.sub(" ", sense.glosses[-1]).strip() if sense.glosses else ""
        if is_service_sense(sense) or not gloss:
            if stats:
                stats.dropped_senses += 1
            continue
        senses.append(
            SenseRow(gloss=gloss, tags=sense.tags, examples=sense.examples[:MAX_EXAMPLES])
        )
    if not senses:
        return None
    return EntryRow(
        lemma=entry.word, pos=map_pos(entry.pos), ipa=pick_ipa(entry.sounds), senses=tuple(senses)
    )


def iter_rows(
    entries: Iterable[kaikki.Entry], min_zipf: float | None, stats: BuildStats
) -> Iterator[EntryRow]:
    for entry in entries:
        stats.read += 1
        row = convert_entry(entry, stats)
        if row is None:
            stats.no_senses += 1
            continue
        if min_zipf and zipf_frequency(normalize_key(row.lemma), "en") < min_zipf:
            stats.cut_by_zipf += 1
            continue
        stats.kept += 1
        yield row


def _fix_ranks(path: Path) -> None:
    """Статьи с ``lemma == key`` — первыми, дальше порядок вставки (= порядок дампа)."""
    con = sqlite3.connect(path)
    con.execute(
        "UPDATE entries SET rank = r.n FROM (SELECT id, ROW_NUMBER() OVER "
        "(PARTITION BY key ORDER BY lemma != key, id) - 1 AS n FROM entries) AS r "
        "WHERE entries.id = r.id"
    )
    con.commit()
    con.execute("VACUUM")
    con.close()


def build_pack(
    dump: Path,
    out_path: Path,
    version: str,
    min_zipf: float | None = None,
) -> BuildStats:
    """Собирает ``out_path`` из ``dump``. ``min_zipf`` ``None`` или 0 — без отсечения."""
    stats = BuildStats()
    day = f"{version[:4]}-{version[4:6]}-{version[6:8]}"
    extra = {"zipf_threshold": str(min_zipf)} if min_zipf else {}
    meta = PackMeta(PACK_ID, version, f"kaikki.org dump {day}", LICENSE, extra)
    write_en_en(out_path, meta, iter_rows(kaikki.read_entries(dump), min_zipf, stats))
    _fix_ranks(out_path)
    return stats


def build_auto(
    dump: Path,
    out_dir: Path,
    version: str | None = None,
    min_zipf: float | None = None,
    size_limit: int = SIZE_LIMIT_BYTES,
    cut_zipf: float = DEFAULT_CUT_ZIPF,
) -> tuple[Path, BuildStats, float | None]:
    """Сборка с автоотсечением: возвращает (файл, счётчики, применённый порог)."""
    version = version or kaikki.read_version(dump)
    if not version:
        raise SystemExit(f"нет версии дампа ({kaikki.version_path(dump)}): задайте --version")
    out = out_dir / f"{PACK_ID}-{version}.sqlite"
    stats = build_pack(dump, out, version, min_zipf)
    applied = min_zipf or None
    if min_zipf is None and out.stat().st_size > size_limit:
        print(f"{out.stat().st_size} байт > {size_limit}: пересборка с --min-zipf {cut_zipf}")
        stats = build_pack(dump, out, version, cut_zipf)
        applied = cut_zipf
    return out, stats, applied


# ---------------------------------------------------------------- отчёт

SAMPLE_WORDS = ("cat", "run", "book", "ephemeral", "pond")


def report(pack: Path, samples: int = 5, words: Iterable[str] = SAMPLE_WORDS) -> str:
    """Текст отчёта: число лемм, размер, примеры статей."""
    con = sqlite3.connect(f"file:{pack}?mode=ro", uri=True)
    meta = dict(con.execute("SELECT key, value FROM meta"))
    n_entries = con.execute("SELECT count(*) FROM entries").fetchone()[0]
    n_keys = con.execute("SELECT count(DISTINCT key) FROM entries").fetchone()[0]
    n_senses = con.execute("SELECT count(*) FROM senses").fetchone()[0]
    n_examples = con.execute("SELECT count(*) FROM examples").fetchone()[0]
    size = pack.stat().st_size
    lines = [
        f"пакет: {pack.name} (версия {meta.get('version')}, {meta.get('source')})",
        f"порог Zipf: {meta.get('zipf_threshold', 'нет')}",
        f"лемм (разных ключей): {n_keys}; статей (лемма+pos): {n_entries}",
        f"значений: {n_senses}; примеров: {n_examples}",
        f"размер: {size} байт ({size / 1048576:.1f} МБ); лимит {SIZE_LIMIT_BYTES // 1048576} МБ",
        "",
    ]
    keys = [w for w in words if con.execute("SELECT 1 FROM entries WHERE key = ?", (w,)).fetchone()]
    if len(keys) < samples and n_entries:
        step = max(1, n_keys // samples)
        all_keys = [r[0] for r in con.execute("SELECT DISTINCT key FROM entries ORDER BY key")]
        keys += [k for k in all_keys[::step] if k not in keys]
    for key in keys[:samples]:
        lines.append(f"=== {key}")
        entries = con.execute(
            "SELECT id, lemma, pos, ipa FROM entries WHERE key = ? ORDER BY rank", (key,)
        ).fetchall()
        for eid, lemma, pos, ipa in entries:
            lines.append(f"{lemma} ({pos}) {ipa or ''}".rstrip())
            senses = con.execute(
                "SELECT id, gloss, tags FROM senses WHERE entry_id = ? ORDER BY idx LIMIT 3",
                (eid,),
            ).fetchall()
            for sid, gloss, tags in senses:
                lines.append(f"  - {gloss}" + (f" {tags}" if tags else ""))
                ex = con.execute(
                    "SELECT text FROM examples WHERE sense_id = ? ORDER BY idx LIMIT 1", (sid,)
                ).fetchone()
                if ex:
                    lines.append(f"      e.g. {ex[0][:120]}")
    con.close()
    return "\n".join(lines)


def _newest_pack(out_dir: Path) -> Path:
    packs = sorted(out_dir.glob(f"{PACK_ID}-*.sqlite"))
    if not packs:
        raise SystemExit(f"нет {PACK_ID}-*.sqlite в {out_dir}: сначала build")
    return packs[-1]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="build.pack_en_en", description="Пакет en-en")
    sub = parser.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="собрать en-en из дампа kaikki.org")
    b.add_argument("--dump", type=Path, default=DEFAULT_DUMP)
    b.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    b.add_argument("--version", help="по умолчанию — версия дампа (файл .version рядом)")
    b.add_argument(
        "--min-zipf",
        type=float,
        default=None,
        help="отбросить статьи с Zipf ниже порога; без флага — только если пакет больше "
        f"{SIZE_LIMIT_BYTES // 1048576} МБ (тогда {DEFAULT_CUT_ZIPF}); 0 — никогда",
    )
    r = sub.add_parser("report", help="отчёт: число лемм, размер, 5 статей")
    r.add_argument("--pack", type=Path, help="по умолчанию — новейший в --out-dir")
    r.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args(argv)

    if args.cmd == "build":
        out, stats, applied = build_auto(args.dump, args.out_dir, args.version, args.min_zipf)
        print(f"{out}: статей {stats.kept} из {stats.read}, порог Zipf: {applied or 'нет'}")
        print(
            f"без значений: {stats.no_senses}; отсечено по Zipf: {stats.cut_by_zipf}; "
            f"выброшено служебных значений: {stats.dropped_senses}"
        )
        print(report(out))
        return 0
    print(report(args.pack or _newest_pack(args.out_dir)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
