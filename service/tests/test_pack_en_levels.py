"""Тесты сборки en-levels на выборках из fixtures/cefr/ и настоящих данных wordfreq."""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from build.pack_en_levels import (
    LevelsError,
    build_pack,
    build_rows,
    merge_cefr,
    parse_cefr_csv,
)
from build.schema import DDL_EN_LEVELS, SCHEMA_VERSION
from build.zipf_thresholds import estimate_cefr

CEFR_DIR = Path(__file__).resolve().parent.parent / "fixtures" / "cefr"
CEFRJ = CEFR_DIR / "cefrj-sample.csv"
OCTANOVE = CEFR_DIR / "octanove-sample.csv"
EXTRA = 3000


@pytest.fixture(scope="module")
def pack(tmp_path_factory: pytest.TempPathFactory) -> sqlite3.Connection:
    out = tmp_path_factory.mktemp("pack") / "en-levels-20260101.sqlite"
    build_pack(CEFRJ, OCTANOVE, out, "20260101", extra_words=EXTRA)
    return sqlite3.connect(f"file:{out}?mode=ro", uri=True)


def row(con: sqlite3.Connection, lemma: str, pos: str):
    return con.execute(
        "SELECT cefr, zipf, estimated FROM levels WHERE lemma = ? AND pos = ?", (lemma, pos)
    ).fetchone()


def test_ten_known_words(pack: sqlite3.Connection) -> None:
    # (lemma, pos, ожидаемый cefr, диапазон zipf)
    cases = [
        ("the", "det", "a1", (7.0, 8.0)),
        ("dog", "noun", "a1", (4.5, 5.8)),
        ("abandon", "verb", "b1", (3.5, 4.6)),
        ("quickly", "adv", "a1", (4.5, 5.8)),
        ("exterior", "noun", "c1", (3.5, 4.8)),
        ("ephemeral", "adj", "c2", (2.5, 3.5)),
        ("remonstrate", "verb", "c2", (1.0, 2.5)),
        ("curriculum", "noun", "b1", (3.5, 4.8)),  # B1 в CEFR-J, C2 в Octanove: min
        ("can", "verb", "a1", (6.0, 7.5)),  # modal auxiliary -> verb
        ("to", "particle", "a1", (7.0, 8.0)),  # infinitive-to
    ]
    for lemma, pos, cefr, (lo, hi) in cases:
        got = row(pack, lemma, pos)
        assert got is not None, (lemma, pos)
        assert got[0] == cefr, (lemma, got)
        assert got[1] is not None
        assert lo <= got[1] <= hi, (lemma, got[1])
        assert got[2] == 0


def test_schema_and_meta(pack: sqlite3.Connection) -> None:
    assert pack.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
    sql = pack.execute("SELECT sql FROM sqlite_master WHERE name = 'levels'").fetchone()[0]
    assert sql + ";" == DDL_EN_LEVELS
    meta = dict(pack.execute("SELECT key, value FROM meta"))
    assert meta["pack_id"] == "en-levels"
    assert meta["version"] == "20260101"
    assert "CC BY-SA" in meta["license"]


def test_slash_variants_become_separate_lemmas(pack: sqlite3.Connection) -> None:
    for lemma in ("color", "colour", "cafe", "café", "analyze", "analyse", "a.m.", "am"):
        assert pack.execute("SELECT 1 FROM levels WHERE lemma = ?", (lemma,)).fetchone(), lemma
    assert row(pack, "a.m.", "adv")[0] == "a1"
    # `AM` после нормализации совпадает с `am`: одна строка (am, adv), не две
    assert pack.execute(
        "SELECT COUNT(*) FROM levels WHERE lemma = 'am' AND pos = 'adv'"
    ).fetchone() == (1,)
    # у `am` есть и be-verb -> verb
    assert row(pack, "am", "verb")[0] == "a1"


def test_min_level_when_lists_overlap(pack: sqlite3.Connection) -> None:
    assert row(pack, "rich", "adj")[0] == "a1"  # A1 и C1
    assert row(pack, "circuit", "noun")[0] == "b2"  # B2 и C2
    assert row(pack, "conceive", "verb")[0] == "b2"  # B2 и C1
    assert row(pack, "accessibility", "noun")[0] == "b2"


def test_source_quirks(pack: sqlite3.Connection) -> None:
    assert row(pack, "turn to", "verb")[0] == "c1"  # хвостовой пробел
    assert row(pack, "laud", "verb")[0] == "c2"
    assert row(pack, "batter", "any")[0] == "c1"  # пустая часть речи
    assert row(pack, "accident", "noun")[0] == "a2"  # поле в кавычках с запятой


def test_frequent_words_outside_cefr(pack: sqlite3.Connection) -> None:
    got = row(pack, "internet", "any")
    assert got is not None
    cefr, zipf, estimated = got
    assert estimated == 1
    assert zipf is not None and cefr == estimate_cefr(zipf)
    assert zipf is not None and 4.5 <= zipf <= 6.5
    # слово из CEFR не дублируется строкой any (кроме явной пустой pos у batter)
    assert row(pack, "dog", "any") is None
    # токены без букв отброшены
    assert pack.execute("SELECT COUNT(*) FROM levels WHERE lemma = '1'").fetchone() == (0,)
    n_extra = pack.execute("SELECT COUNT(*) FROM levels WHERE estimated = 1").fetchone()[0]
    assert 0 < n_extra <= EXTRA


def test_estimated_flag_separates_sources(pack: sqlite3.Connection) -> None:
    # слова из CEFR-списков: estimated = 0, уровень есть всегда
    assert pack.execute(
        "SELECT COUNT(*) FROM levels WHERE estimated = 0 AND cefr IS NULL"
    ).fetchone() == (0,)
    # у всех оценённых строк уровень совпадает с порогами
    for cefr, zipf in pack.execute("SELECT cefr, zipf FROM levels WHERE estimated = 1"):
        assert zipf is not None
        assert cefr == estimate_cefr(zipf)
    # настоящий CEFR не перезаписывается оценкой
    got = row(pack, "ephemeral", "adj")
    assert got[0] == "c2" and got[2] == 0


def test_null_zipf_stays_without_level() -> None:
    rows = build_rows(
        {("dog", "noun"): "a1"},
        extra_words=3,
        zipf=lambda w: None if w == "ghost" else 5.5 if w == "cat" else 1.0,
        frequent=lambda _n: ["cat", "ghost", "dog"],
    )
    by_lemma = {(r.lemma, r.pos): r for r in rows}
    assert by_lemma[("dog", "noun")].estimated is False
    assert by_lemma[("cat", "any")].cefr == "a1"
    assert by_lemma[("cat", "any")].estimated is True
    assert by_lemma[("ghost", "any")].cefr is None
    assert by_lemma[("ghost", "any")].estimated is False


def test_only_valid_values(pack: sqlite3.Connection) -> None:
    bad = pack.execute(
        "SELECT COUNT(*) FROM levels WHERE lemma != lower(trim(lemma)) OR lemma LIKE '%/%'"
    ).fetchone()
    assert bad == (0,)


def test_merge_takes_minimum() -> None:
    a = parse_cefr_csv(CEFRJ)
    b = parse_cefr_csv(OCTANOVE)
    assert merge_cefr(b, a) == merge_cefr(a, b)


def test_unknown_pos_or_level_is_error(tmp_path: Path) -> None:
    bad_pos = tmp_path / "pos.csv"
    bad_pos.write_text("headword,pos,CEFR\nfoo,gerund,A1\n", encoding="utf-8")
    with pytest.raises(LevelsError, match="часть речи"):
        parse_cefr_csv(bad_pos)
    bad_level = tmp_path / "level.csv"
    bad_level.write_text("headword,pos,CEFR\nfoo,noun,D9\n", encoding="utf-8")
    with pytest.raises(LevelsError, match="уровень"):
        parse_cefr_csv(bad_level)
    bad_header = tmp_path / "header.csv"
    bad_header.write_text("word,pos\nfoo,noun\n", encoding="utf-8")
    with pytest.raises(LevelsError, match="колонки"):
        parse_cefr_csv(bad_header)
