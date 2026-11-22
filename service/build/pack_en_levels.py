"""Сборка пакета en-levels: уровни CEFR (CEFR-J, Octanove) и частотность (wordfreq).

Источники: CSV из https://github.com/openlanguageprofiles/olp-en-cefrj (CC BY-SA 4.0)
и пакет ``wordfreq`` (данные CC BY-SA 4.0, код Apache 2.0).

Запуск (из ``service/``)::

    uv run python -m build.pack_en_levels fetch   # CSV -> data/cefr/
    uv run python -m build.pack_en_levels build   # data/cefr/ -> data/packs/

Правила сведения:

* Заголовок ``a.m./A.M./am/AM`` — варианты написания через ``/``. Каждый вариант
  становится отдельной леммой с той же частью речи и уровнем; после ``normalize_key``
  одинаковые варианты схлопываются (``a.m.``, ``am``).
* Часть речи из источника приводится к списку схемы (``POS_MAP``). Пустая часть речи
  — ``any``. Многословные записи (``according to``) остаются со своей частью речи.
* Одна пара (лемма, pos) в нескольких строках или в обоих списках — берётся
  **минимальный** уровень: слово, известное на низком уровне, не считается трудным.
* Для всех лемм CEFR добавляется ``zipf`` (``NULL``, если wordfreq слова не знает).
* Затем добавляются топ-``extra_words`` частотных слов wordfreq, которых нет среди лемм
  CEFR: ``pos = any``; уровень — оценка по Zipf (``zipf_thresholds.ZIPF_THRESHOLDS``),
  ``estimated = 1``. Строки без Zipf остаются с ``cefr = NULL``. Слова из CEFR-списков
  всегда ``estimated = 0``.
* Подбор порогов: ``fit`` — по леммам CEFR, уровень леммы — минимум по частям речи,
  только однословные (см. ``fit_samples``).
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
import sys
import urllib.request
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from wordfreq import top_n_list, zipf_frequency

from build.packdb import LevelRow, PackMeta, write_en_levels
from build.schema import CEFR_VALUES, POS_ANY, normalize_key
from build.zipf_thresholds import (
    ZIPF_THRESHOLDS,
    estimate_cefr,
    evaluate,
    fit_thresholds,
    split_samples,
)

BASE_URL = "https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/master/"
CEFRJ_NAME = "cefrj-vocabulary-profile-1.5.csv"
OCTANOVE_NAME = "octanove-vocabulary-profile-c1c2-1.0.csv"

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DEFAULT_CEFR_DIR = DATA_DIR / "cefr"
DEFAULT_OUT_DIR = DATA_DIR / "packs"

#: Часть речи источников -> `pos` схемы. `vern` — опечатка в Octanove (``remonstrate``).
POS_MAP = {
    "noun": "noun",
    "verb": "verb",
    "adjective": "adj",
    "adverb": "adv",
    "pronoun": "pron",
    "preposition": "prep",
    "conjunction": "conj",
    "interjection": "intj",
    "determiner": "det",
    "number": "num",
    "infinitive-to": "particle",
    "modal auxiliary": "verb",
    "be-verb": "verb",
    "do-verb": "verb",
    "have-verb": "verb",
    "vern": "verb",
    "": POS_ANY,
}

LICENSE = "CC BY-SA 4.0 (CEFR-J, Octanove, wordfreq data)"
SOURCE = "CEFR-J Wordlist 1.5, Octanove Vocabulary Profile C1/C2 1.0, wordfreq"

_HAS_LETTER = re.compile(r"[^\W\d_]")


class LevelsError(ValueError):
    """Исходные данные не соответствуют ожидаемому формату."""


@dataclass(frozen=True)
class CefrEntry:
    lemma: str  # нормализованная
    pos: str
    cefr: str


def parse_cefr_csv(path: Path) -> list[CefrEntry]:
    """Читает CSV (колонки ``headword,pos,CEFR,...``) в список записей."""
    entries: list[CefrEntry] = []
    with path.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for col in ("headword", "pos", "CEFR"):
            if col not in (reader.fieldnames or []):
                raise LevelsError(f"{path.name}: нет колонки {col!r}")
        for line, row in enumerate(reader, start=2):
            raw_pos = (row["pos"] or "").strip().lower()
            if raw_pos not in POS_MAP:
                raise LevelsError(f"{path.name}:{line}: неизвестная часть речи {raw_pos!r}")
            pos = POS_MAP[raw_pos]
            cefr = (row["CEFR"] or "").strip().lower()
            if cefr not in CEFR_VALUES:
                raise LevelsError(f"{path.name}:{line}: неизвестный уровень {cefr!r}")
            for variant in (row["headword"] or "").split("/"):
                lemma = normalize_key(variant)
                if lemma:
                    entries.append(CefrEntry(lemma, pos, cefr))
    return entries


def merge_cefr(*sources: list[CefrEntry]) -> dict[tuple[str, str], str]:
    """Сводит записи в ``(лемма, pos) -> уровень``; при конфликте — минимальный уровень."""
    merged: dict[tuple[str, str], str] = {}
    for entries in sources:
        for e in entries:
            key = (e.lemma, e.pos)
            old = merged.get(key)
            if old is None or CEFR_VALUES.index(e.cefr) < CEFR_VALUES.index(old):
                merged[key] = e.cefr
    return merged


def zipf_or_none(word: str) -> float | None:
    """Zipf слова по wordfreq; ``None``, если слова там нет (wordfreq отдаёт 0.0)."""
    value = zipf_frequency(word, "en")
    return round(value, 2) if value > 0 else None


def frequent_words(n: int) -> list[str]:
    """Топ-``n`` слов wordfreq в нормализованном виде, без токенов без букв (``1``, ``%``)."""
    seen: set[str] = set()
    result: list[str] = []
    for word in top_n_list("en", n):
        key = normalize_key(word)
        if key and key not in seen and _HAS_LETTER.search(key):
            seen.add(key)
            result.append(key)
    return result


def build_rows(
    cefr: dict[tuple[str, str], str],
    extra_words: int = 50_000,
    zipf: Callable[[str], float | None] = zipf_or_none,
    frequent: Callable[[int], list[str]] = frequent_words,
    thresholds: Sequence[float] = ZIPF_THRESHOLDS,
) -> list[LevelRow]:
    """Строки пакета: леммы CEFR с zipf плюс частотные слова вне CEFR с оценкой уровня."""
    rows = [
        LevelRow(lemma, pos, level, zipf(lemma), False)
        for (lemma, pos), level in sorted(cefr.items())
    ]
    known = {lemma for lemma, _ in cefr}
    for word in frequent(extra_words):
        if word not in known:
            z = zipf(word)
            level = estimate_cefr(z, thresholds)
            rows.append(LevelRow(word, POS_ANY, level, z, level is not None))
    return rows


def fit_samples(
    cefr: dict[tuple[str, str], str],
    zipf: Callable[[str], float | None] = zipf_or_none,
) -> list[tuple[str, float, int]]:
    """Выборка для подбора порогов: ``(лемма, zipf, индекс уровня)``.

    Уровень леммы — минимум по частям речи: Zipf у wordfreq один на написание, а не на
    пару (лемма, pos), и многие записи C1/C2 Octanove — редкие значения частых слов
    (``rich`` C1 при A1). Многословные леммы (пробел, дефис) исключены: Zipf фразы в
    wordfreq считается из частот частей и несравним с частотой слова.
    """
    per_lemma: dict[str, int] = {}
    for (lemma, _pos), level in cefr.items():
        idx = CEFR_VALUES.index(level)
        per_lemma[lemma] = min(per_lemma.get(lemma, idx), idx)
    samples = []
    for lemma, idx in sorted(per_lemma.items()):
        if " " in lemma or "-" in lemma:
            continue
        z = zipf(lemma)
        if z is not None:
            samples.append((lemma, z, idx))
    return samples


def fit_report(cefr: dict[tuple[str, str], str]) -> str:
    """Подбирает пороги на обучающей части и описывает точность на отложенной."""
    train, test = split_samples(fit_samples(cefr))
    fitted = fit_thresholds([(z, i) for _, z, i in train])
    lines = [f"samples: {len(train)} train, {len(test)} held-out"]
    lines.append(f"fitted thresholds (a1,a2,b1,b2,c1): {fitted}")
    lines.append(f"config ZIPF_THRESHOLDS:              {tuple(ZIPF_THRESHOLDS)}")
    for name, part in (("train", train), ("held-out", test)):
        acc = evaluate([(z, i) for _, z, i in part], fitted)
        lines.append(
            f"{name}: exact {acc.exact:.3f}, within +-1 {acc.within_one:.3f}, "
            f"mean |error| {acc.mean_abs_error:.3f} (n={acc.n})"
        )
    return "\n".join(lines)


def build_pack(
    cefrj_csv: Path,
    octanove_csv: Path,
    out_path: Path,
    version: str,
    extra_words: int = 50_000,
) -> list[LevelRow]:
    """Собирает ``en-levels`` из двух CSV и пишет SQLite в ``out_path``."""
    merged = merge_cefr(parse_cefr_csv(cefrj_csv), parse_cefr_csv(octanove_csv))
    rows = build_rows(merged, extra_words)
    meta = PackMeta("en-levels", version, SOURCE, LICENSE)
    write_en_levels(out_path, meta, rows)
    return rows


def fetch(dest_dir: Path) -> list[Path]:
    """Скачивает оба CSV в ``dest_dir`` (запускает человек: нужна сеть до GitHub)."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for name in (CEFRJ_NAME, OCTANOVE_NAME):
        target = dest_dir / name
        with urllib.request.urlopen(BASE_URL + name, timeout=60) as resp:
            target.write_bytes(resp.read())
        paths.append(target)
    return paths


def _version_today() -> str:
    return dt.datetime.now(dt.UTC).strftime("%Y%m%d")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="build.pack_en_levels")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_fetch = sub.add_parser("fetch", help="скачать CSV CEFR-J и Octanove")
    p_fetch.add_argument("--dest", type=Path, default=DEFAULT_CEFR_DIR)
    p_fit = sub.add_parser("fit", help="подобрать пороги Zipf -> CEFR и показать точность")
    p_fit.add_argument("--cefrj", type=Path, default=DEFAULT_CEFR_DIR / CEFRJ_NAME)
    p_fit.add_argument("--octanove", type=Path, default=DEFAULT_CEFR_DIR / OCTANOVE_NAME)
    p_fit.add_argument("--examples", type=int, default=0, help="показать N оценённых слов")
    p_build = sub.add_parser("build", help="собрать en-levels из локальных CSV")
    p_build.add_argument("--cefrj", type=Path, default=DEFAULT_CEFR_DIR / CEFRJ_NAME)
    p_build.add_argument("--octanove", type=Path, default=DEFAULT_CEFR_DIR / OCTANOVE_NAME)
    p_build.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    p_build.add_argument("--version", default=_version_today())
    p_build.add_argument("--extra-words", type=int, default=50_000)
    args = parser.parse_args(argv)

    if args.cmd == "fetch":
        for path in fetch(args.dest):
            print(path)
        return 0
    if args.cmd == "fit":
        merged = merge_cefr(parse_cefr_csv(args.cefrj), parse_cefr_csv(args.octanove))
        print(fit_report(merged))
        if args.examples:
            print(f"examples ({args.examples} estimated words, evenly spaced by frequency rank):")
            rows = [r for r in build_rows(merged) if r.estimated]
            step = max(1, len(rows) // args.examples)
            for r in rows[::step][: args.examples]:
                print(f"  {r.lemma}\tzipf {r.zipf}\t{r.cefr}")
        return 0
    out = args.out_dir / f"en-levels-{args.version}.sqlite"
    rows = build_pack(args.cefrj, args.octanove, out, args.version, args.extra_words)
    with_cefr = sum(r.cefr is not None for r in rows)
    print(f"{out}: {len(rows)} rows ({with_cefr} with cefr), {out.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
