"""Сборка en-en на выборке из 100 строк дампа kaikki (fixtures/kaikki/kaikki-100.jsonl)."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest
from wordfreq import zipf_frequency

from build import pack_en_en
from build.pack_en_en import build_auto, build_pack, report
from build.schema import META_KEYS, POS_VALUES, SCHEMA_VERSION, normalize_key

DUMP = Path(__file__).resolve().parent.parent / "fixtures" / "kaikki" / "kaikki-100.jsonl"
VERSION = "20260101"


def connect(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def scalar(con: sqlite3.Connection, sql: str, *args: object) -> object:
    return con.execute(sql, args).fetchone()[0]


@pytest.fixture(scope="module")
def pack_path(tmp_path_factory: pytest.TempPathFactory) -> Path:
    out = tmp_path_factory.mktemp("pack") / f"en-en-{VERSION}.sqlite"
    build_pack(DUMP, out, VERSION)
    return out


@pytest.fixture(scope="module")
def con(pack_path: Path) -> sqlite3.Connection:
    return connect(pack_path)


def test_schema_and_meta(con: sqlite3.Connection) -> None:
    assert scalar(con, "PRAGMA user_version") == SCHEMA_VERSION
    meta = dict(con.execute("SELECT key, value FROM meta"))
    assert set(META_KEYS) <= set(meta)
    assert meta["pack_id"] == "en-en"
    assert meta["version"] == VERSION
    assert meta["source"] == "kaikki.org dump 2026-01-01"
    assert meta["license"] == "CC BY-SA 4.0"
    assert "zipf_threshold" not in meta
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    assert tables == {"meta", "entries", "senses", "examples"}
    assert con.execute("PRAGMA foreign_key_check").fetchall() == []


def test_cat_noun(con: sqlite3.Connection) -> None:
    rows = con.execute(
        "SELECT id, lemma, pos, ipa, rank FROM entries WHERE key = 'cat' AND pos = 'noun' "
        "ORDER BY rank"
    ).fetchall()
    assert len(rows) >= 2
    eid, lemma, pos, ipa, rank = rows[0]
    assert (lemma, pos, ipa, rank) == ("cat", "noun", "/ˈkæt/", 0)
    glosses = [g for (g,) in con.execute("SELECT gloss FROM senses WHERE entry_id = ?", (eid,))]
    assert "A mammal of the family Felidae." in glosses
    assert "Terms relating to animals." not in glosses  # берётся последний элемент цепочки
    sense_id = scalar(
        con,
        "SELECT id FROM senses WHERE entry_id = ? AND gloss = 'A mammal of the family Felidae.'",
        eid,
    )
    examples = [
        t for (t,) in con.execute("SELECT text FROM examples WHERE sense_id = ?", (sense_id,))
    ]
    assert len(examples) == 1
    assert examples[0].startswith("Mammals need two genes")
    tags = scalar(con, "SELECT tags FROM senses WHERE id = ?", sense_id)
    assert json.loads(str(tags)) == ["countable"]


def test_examples_capped_and_ordered(con: sqlite3.Connection) -> None:
    counts = [c for (c,) in con.execute("SELECT count(*) FROM examples GROUP BY sense_id")]
    assert max(counts) == pack_en_en.MAX_EXAMPLES
    assert (
        scalar(
            con,
            "SELECT count(*) FROM (SELECT min(idx) m FROM examples GROUP BY sense_id) WHERE m != 0",
        )
        == 0
    )


def test_pos_mapped_to_schema(con: sqlite3.Connection) -> None:
    used = {p for (p,) in con.execute("SELECT DISTINCT pos FROM entries")}
    assert used <= set(POS_VALUES)
    assert "other" in used  # character / symbol в выборке


def test_pies_has_no_service_gloss(con: sqlite3.Connection) -> None:
    # `pies` в выборке состоит только из form-of («plural of pie», «third-person ...»)
    assert scalar(con, "SELECT count(*) FROM entries WHERE key = 'pies'") == 0
    assert scalar(con, "SELECT count(*) FROM senses WHERE gloss LIKE 'plural of %'") == 0
    # book: значение `simple past of bake` (form-of) выброшено, обычные остались
    assert scalar(con, "SELECT count(*) FROM senses WHERE gloss LIKE 'simple past of%'") == 0
    assert scalar(con, "SELECT count(*) FROM entries WHERE key = 'book'") >= 1
    assert scalar(con, "SELECT count(*) FROM entries WHERE key = 'pie'") >= 1


def test_alt_of_senses_kept(con: sqlite3.Connection) -> None:
    tags = scalar(
        con,
        "SELECT tags FROM senses WHERE gloss LIKE 'Initialism of gross domestic product%'",
    )
    assert "alt-of" in json.loads(str(tags))


def test_every_entry_has_senses_and_valid_rank(con: sqlite3.Connection) -> None:
    orphans = scalar(
        con,
        "SELECT count(*) FROM entries e WHERE NOT EXISTS "
        "(SELECT 1 FROM senses s WHERE s.entry_id = e.id)",
    )
    assert orphans == 0
    for key, n, mx in con.execute("SELECT key, count(*), max(rank) FROM entries GROUP BY key"):
        assert mx == n - 1, key
    for lemma, key in con.execute("SELECT lemma, key FROM entries"):
        assert key == normalize_key(lemma)


def test_rank_puts_exact_lemma_first(tmp_path: Path) -> None:
    dump = tmp_path / "d.jsonl"
    rows = [
        {
            "word": "Polish",
            "pos": "adj",
            "lang_code": "en",
            "senses": [{"glosses": ["Of Poland."]}],
        },
        {"word": "polish", "pos": "verb", "lang_code": "en", "senses": [{"glosses": ["To rub."]}]},
    ]
    dump.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    out = tmp_path / "en-en-20260101.sqlite"
    build_pack(dump, out, VERSION)
    got = (
        connect(out)
        .execute("SELECT lemma FROM entries WHERE key = 'polish' ORDER BY rank")
        .fetchall()
    )
    assert got == [("polish",), ("Polish",)]


def test_zipf_cut(pack_path: Path, tmp_path: Path) -> None:
    out = tmp_path / "en-en-20260101.sqlite"
    stats = build_pack(DUMP, out, VERSION, min_zipf=3.5)
    cut = connect(out)
    assert dict(cut.execute("SELECT key, value FROM meta"))["zipf_threshold"] == "3.5"
    full_keys = {k for (k,) in connect(pack_path).execute("SELECT key FROM entries")}
    cut_keys = {k for (k,) in cut.execute("SELECT key FROM entries")}
    assert cut_keys < full_keys
    assert stats.cut_by_zipf > 0
    assert "floccinaucinihilipilification" in full_keys
    assert "floccinaucinihilipilification" not in cut_keys
    assert "cat" in cut_keys  # zipf 4.78
    assert all(zipf_frequency(k, "en") >= 3.5 for k in cut_keys)
    assert {k for k in full_keys if zipf_frequency(k, "en") >= 3.5} == cut_keys


def test_auto_cut_only_above_size_limit(tmp_path: Path) -> None:
    out, _, applied = build_auto(DUMP, tmp_path / "a", VERSION)
    assert applied is None  # маленький пакет: отсечения нет
    assert out.name == f"en-en-{VERSION}.sqlite"
    out, _, applied = build_auto(DUMP, tmp_path / "b", VERSION, size_limit=1, cut_zipf=3.5)
    assert applied == 3.5
    assert dict(connect(out).execute("SELECT key, value FROM meta"))["zipf_threshold"] == "3.5"
    # явный 0 — отсечения нет, даже если пакет больше лимита
    _, _, applied = build_auto(DUMP, tmp_path / "c", VERSION, min_zipf=0, size_limit=1)
    assert applied is None


def test_version_from_dump(tmp_path: Path) -> None:
    dump = tmp_path / "kaikki.org-dictionary-English.jsonl"
    dump.write_bytes(DUMP.read_bytes())
    (tmp_path / (dump.name + ".version")).write_text("20250305\n")
    out, _, _ = build_auto(dump, tmp_path / "out")
    assert out.name == "en-en-20250305.sqlite"
    meta = dict(connect(out).execute("SELECT key, value FROM meta"))
    assert meta["version"] == "20250305"
    assert meta["source"] == "kaikki.org dump 2025-03-05"
    with pytest.raises(SystemExit):
        build_auto(DUMP, tmp_path / "out2")  # нет .version


def test_report(pack_path: Path) -> None:
    text = report(pack_path)
    assert "лемм (разных ключей):" in text
    assert "размер:" in text
    assert "=== cat" in text
    assert text.count("=== ") == 5


def test_cli_build_and_report(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    code = pack_en_en.main(
        ["build", "--dump", str(DUMP), "--out-dir", str(tmp_path), "--version", VERSION]
    )
    assert code == 0
    assert (tmp_path / f"en-en-{VERSION}.sqlite").exists()
    capsys.readouterr()
    assert pack_en_en.main(["report", "--out-dir", str(tmp_path)]) == 0
    assert "=== cat" in capsys.readouterr().out
