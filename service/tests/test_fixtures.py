"""Мини-пакеты в fixtures/ соответствуют задокументированной схеме."""

import json
import sqlite3
from pathlib import Path

import pytest

from build import fixtures, schema
from build.packdb import sha256_file

PACK_IDS = ("en-en", "en-forms", "en-levels")
FIXTURES = fixtures.FIXTURES_DIR


def _connect(path: Path) -> sqlite3.Connection:
    # Только чтение, как в приложении.
    return sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True)


def _schema_sql(con: sqlite3.Connection) -> list[tuple[str, str]]:
    rows = con.execute(
        "SELECT type, sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name"
    ).fetchall()
    return [(t, " ".join(s.split())) for t, s in rows]


def _expected_schema(pack_id: str, tmp_path: Path) -> list[tuple[str, str]]:
    ref = sqlite3.connect(tmp_path / f"{pack_id}-ref.sqlite")
    ref.executescript(schema.DDL_META)
    ref.executescript(schema.PACK_DDL[pack_id])
    result = _schema_sql(ref)
    ref.close()
    return result


@pytest.fixture(scope="module")
def manifest() -> dict:
    return json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))


def test_manifest_format(manifest: dict) -> None:
    assert manifest["manifest_version"] == schema.MANIFEST_VERSION
    assert manifest["generated_at"].endswith("Z")
    assert [p["id"] for p in manifest["packs"]] == list(PACK_IDS)
    for pack in manifest["packs"]:
        assert set(pack) == {
            "id",
            "version",
            "schema_version",
            "size",
            "sha256",
            "path",
            "license",
        }
        assert schema.VERSION_RE.match(pack["version"])
        assert pack["schema_version"] == schema.SCHEMA_VERSION
        assert pack["path"] == f"packs/{pack['id']}-{pack['version']}.sqlite"
        assert len(pack["sha256"]) == 64
        assert pack["sha256"] == pack["sha256"].lower()


def test_manifest_matches_files(manifest: dict) -> None:
    for pack in manifest["packs"]:
        path = FIXTURES / pack["path"]
        assert path.stat().st_size == pack["size"]
        assert sha256_file(path) == pack["sha256"]


@pytest.mark.parametrize("pack_id", PACK_IDS)
def test_pack_schema_and_meta(pack_id: str, manifest: dict, tmp_path: Path) -> None:
    entry = next(p for p in manifest["packs"] if p["id"] == pack_id)
    con = _connect(FIXTURES / entry["path"])
    assert con.execute("PRAGMA user_version").fetchone()[0] == schema.SCHEMA_VERSION
    assert con.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    assert con.execute("PRAGMA foreign_key_check").fetchall() == []
    assert _schema_sql(con) == _expected_schema(pack_id, tmp_path)
    meta = dict(con.execute("SELECT key, value FROM meta"))
    assert set(schema.META_KEYS) <= set(meta)
    assert meta["pack_id"] == pack_id
    assert meta["version"] == entry["version"]
    assert meta["schema_version"] == str(schema.SCHEMA_VERSION)
    assert meta["license"] == entry["license"]


def test_fixtures_regenerate_identically(tmp_path: Path) -> None:
    """Скрипт воспроизводит содержимое закоммиченных файлов."""
    fixtures.build_fixtures(tmp_path)
    for pack_id in PACK_IDS:
        rel = f"packs/{pack_id}-{fixtures.VERSION}.sqlite"
        a, b = _connect(FIXTURES / rel), _connect(tmp_path / rel)
        assert list(a.iterdump()) == list(b.iterdump())


def _all(pack_id: str, query: str, args: tuple = ()) -> list[tuple]:
    path = fixtures.pack_path(FIXTURES, pack_id)
    return _connect(path).execute(query, args).fetchall()


def test_en_en_content() -> None:
    n_keys = _all("en-en", "SELECT COUNT(DISTINCT key) FROM entries")[0][0]
    assert 20 <= n_keys <= 50
    # Ключи нормализованы.
    for (key,) in _all("en-en", "SELECT key FROM entries"):
        assert key == schema.normalize_key(key)
    for (pos,) in _all("en-en", "SELECT DISTINCT pos FROM entries"):
        assert pos in schema.POS_VALUES
    # Один ключ — несколько статей, ранги идут с нуля подряд.
    polish = _all("en-en", "SELECT lemma, rank FROM entries WHERE key = 'polish' ORDER BY rank")
    assert polish == [("Polish", 0), ("polish", 1)]
    go = _all("en-en", "SELECT pos FROM entries WHERE key = 'go' ORDER BY rank")
    assert go == [("verb",), ("noun",)]
    # Нормализация апострофа и многословных ключей.
    assert _all("en-en", "SELECT COUNT(*) FROM entries WHERE key IN ('can''t', 'take off')") == [
        (2,)
    ]
    # Переводы: и по значению, и по статье; примеры есть.
    assert _all("en-en", "SELECT COUNT(*) FROM translations WHERE sense_id IS NULL")[0][0] > 0
    assert _all("en-en", "SELECT COUNT(*) FROM translations WHERE sense_id IS NOT NULL")[0][0] > 0
    assert _all("en-en", "SELECT COUNT(*) FROM examples")[0][0] > 0
    tags = _all("en-en", "SELECT tags FROM senses WHERE tags IS NOT NULL")
    assert all(isinstance(json.loads(t), list) for (t,) in tags)


def test_en_forms_content() -> None:
    rows = _all("en-forms", "SELECT COUNT(DISTINCT form) FROM forms")
    assert 20 <= rows[0][0] <= 50
    for form, lemma, pos in _all("en-forms", "SELECT form, lemma, pos FROM forms"):
        assert form == schema.normalize_key(form)
        assert lemma == schema.normalize_key(lemma)
        assert pos in schema.POS_VALUES
    q = "SELECT lemma FROM forms WHERE form = ? ORDER BY rank"
    assert _all("en-forms", q, ("went",)) == [("go",)]
    assert _all("en-forms", q, ("children",)) == [("child",)]
    assert _all("en-forms", q, ("better",)) == [("good",), ("well",)]
    assert _all("en-forms", q, ("left",)) == [("leave",), ("left",)]
    assert _all("en-forms", q, ("cat",)) == []


def test_en_levels_content() -> None:
    n = _all("en-levels", "SELECT COUNT(DISTINCT lemma) FROM levels")[0][0]
    assert 20 <= n <= 50
    for lemma, pos, cefr, zipf, estimated in _all("en-levels", "SELECT * FROM levels"):
        assert lemma == schema.normalize_key(lemma)
        assert pos in (*schema.POS_VALUES, schema.POS_ANY)
        assert cefr is None or cefr in schema.CEFR_VALUES
        assert zipf is None or 0 <= zipf <= 8
        assert estimated in (0, 1)
    q = "SELECT cefr, estimated FROM levels WHERE lemma = ? ORDER BY pos"
    assert _all("en-levels", q, ("ephemeral",)) == [("c2", 0)]
    assert _all("en-levels", q, ("ubiquitous",)) == [("c1", 1)]
    assert _all("en-levels", q, ("serendipity",)) == [(None, 0)]
    assert _all("en-levels", "SELECT cefr FROM levels WHERE lemma = 'light' ORDER BY pos") == [
        ("b1",),
        ("a2",),
    ]
    assert _all("en-levels", "SELECT zipf FROM levels WHERE lemma = 'mother-in-law'") == [(None,)]
