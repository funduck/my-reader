"""Тесты en-forms на выборке kaikki-forms.jsonl (go, went, child, good, well, better, left)."""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from build.kaikki import Entry, Form, Sense, read_entries
from build.pack_en_forms import build_pack, build_rows
from build.schema import SCHEMA_VERSION, normalize_key

FIXTURE = Path(__file__).resolve().parent.parent / "fixtures" / "kaikki" / "kaikki-forms.jsonl"


@pytest.fixture(scope="module")
def pack(tmp_path_factory: pytest.TempPathFactory) -> sqlite3.Connection:
    out = tmp_path_factory.mktemp("pack") / "en-forms-20260101.sqlite"
    build_pack(FIXTURE, out, "20260101")
    return sqlite3.connect(f"file:{out}?mode=ro", uri=True)


def lookup(con: sqlite3.Connection, form: str) -> list[tuple[str, str, int]]:
    return con.execute(
        "SELECT lemma, pos, rank FROM forms WHERE form = ? ORDER BY rank", (form,)
    ).fetchall()


def test_fixture_reads() -> None:
    assert sum(1 for _ in read_entries(FIXTURE)) == 39


def test_went_is_go(pack: sqlite3.Connection) -> None:
    rows = lookup(pack, "went")
    assert rows[0] == ("go", "verb", 0)
    assert ("wend", "verb") in [(r[0], r[1]) for r in rows]  # archaic past of wend


def test_children_is_child(pack: sqlite3.Connection) -> None:
    rows = lookup(pack, "children")
    assert rows[0] == ("child", "noun", 0)  # childer (archaic plural) follows by alphabet


def test_better_is_good_and_well(pack: sqlite3.Connection) -> None:
    rows = lookup(pack, "better")
    ordered = [r[0] for r in rows]
    assert "good and well" not in ordered
    # good (Zipf 6.12) чаще well (6.03); варианты словоизменения раньше самой формы
    assert ordered.index("good") < ordered.index("well") < ordered.index("better")
    assert [r[2] for r in rows] == list(range(len(rows)))


def test_left_is_leave_and_left(pack: sqlite3.Connection) -> None:
    rows = lookup(pack, "left")
    assert rows[0] == ("leave", "verb", 0)
    assert ("left", "adj", 1) in rows


def test_plain_lemma_has_no_self_row(pack: sqlite3.Connection) -> None:
    assert lookup(pack, "child") == []
    assert lookup(pack, "go") == []


def test_spellings_and_service_rows_are_dropped(pack: sqlite3.Connection) -> None:
    assert lookup(pack, "gud") == []  # alternative
    assert lookup(pack, "no-table-tags") == []
    assert lookup(pack, "glossary") == []
    assert lookup(pack, "-") == []
    assert lookup(pack, "further left") == []  # несколько слов
    assert lookup(pack, "childs") == [("child", "verb", 0)]  # только словоизменение глагола
    assert {(r[0], r[1]) for r in lookup(pack, "goes")} == {("go", "verb"), ("go", "noun")}


def test_archaic_inflections_are_kept(pack: sqlite3.Connection) -> None:
    assert [(r[0], r[1]) for r in lookup(pack, "goeth")] == [("go", "verb")]
    assert [(r[0], r[1]) for r in lookup(pack, "yode")] == [("go", "verb")]


def test_all_keys_are_normalized(pack: sqlite3.Connection) -> None:
    for form, lemma in pack.execute("SELECT form, lemma FROM forms"):
        assert form == normalize_key(form)
        assert lemma == normalize_key(lemma)


def test_self_rows_only_with_other_variants(pack: sqlite3.Connection) -> None:
    for (form,) in pack.execute("SELECT DISTINCT form FROM forms WHERE form = lemma"):
        others = pack.execute(
            "SELECT COUNT(*) FROM forms WHERE form = ? AND lemma != form", (form,)
        ).fetchone()[0]
        assert others > 0


def test_schema_and_meta(pack: sqlite3.Connection) -> None:
    assert pack.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
    meta = dict(pack.execute("SELECT key, value FROM meta"))
    assert meta["pack_id"] == "en-forms"
    assert meta["version"] == "20260101"
    assert meta["schema_version"] == str(SCHEMA_VERSION)
    assert meta["license"] == "CC BY-SA 4.0"
    assert meta["source"]
    cols = [r[1] for r in pack.execute("PRAGMA table_info(forms)")]
    assert cols == ["form", "lemma", "pos", "rank"]
    idx = [r[0] for r in pack.execute("SELECT name FROM sqlite_master WHERE type = 'index'")]
    assert "forms_form" in idx


def test_composite_lemma_stays_whole_when_parts_are_not_headwords() -> None:
    entries = [
        Entry(
            "blacker",
            "adj",
            senses=(Sense(tags=("comparative", "form-of"), form_of=("black and white",)),),
        ),
        Entry("black", "adj", senses=(Sense(),)),
    ]
    rows = build_rows(entries, zipf_of=lambda _w: 0.0)
    assert [(r.form, r.lemma) for r in rows] == [("blacker", "black and white")]


def test_composite_lemma_splits_when_parts_are_headwords() -> None:
    entries = [
        Entry(
            "better",
            "adj",
            senses=(Sense(tags=("comparative", "form-of"), form_of=("good and well",)),),
        ),
        Entry("good", "adj", senses=(Sense(),), forms=(Form("better", ("comparative",)),)),
        Entry("well", "adv", senses=(Sense(),)),
    ]
    rows = build_rows(entries, zipf_of=lambda w: {"good": 6.0, "well": 5.0}.get(w, 0.0))
    assert [(r.lemma, r.pos, r.rank) for r in rows] == [("good", "adj", 0), ("well", "adj", 1)]
