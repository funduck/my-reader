"""T-036: manifest.json по packs/ и `build all` на мини-данных."""

from __future__ import annotations

import json
import shutil
import sqlite3
from pathlib import Path

import pytest

from build import manifest
from build.packdb import sha256_file

SERVICE = Path(__file__).resolve().parent.parent
FIXTURES = SERVICE / "fixtures"


def _root_with_fixture_packs(tmp_path: Path) -> Path:
    shutil.copytree(FIXTURES / "packs", tmp_path / "packs")
    return tmp_path


def test_manifest_from_fixture_packs_equals_fixture_manifest(tmp_path: Path) -> None:
    expected = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
    root = _root_with_fixture_packs(tmp_path)
    out = manifest.write_root_manifest(root, generated_at=expected["generated_at"])
    assert out == root / "manifest.json"
    assert json.loads(out.read_text(encoding="utf-8")) == expected
    # Побайтово: формат записи тот же, что у fixtures/manifest.json.
    assert out.read_bytes() == (FIXTURES / "manifest.json").read_bytes()


def test_manifest_entries_match_files(tmp_path: Path) -> None:
    root = _root_with_fixture_packs(tmp_path)
    doc = json.loads(manifest.write_root_manifest(root).read_text(encoding="utf-8"))
    assert doc["generated_at"].endswith("Z")
    assert [p["id"] for p in doc["packs"]] == ["en-en", "en-forms", "en-levels"]
    for pack in doc["packs"]:
        file = root / pack["path"]
        assert file.stat().st_size == pack["size"]
        assert sha256_file(file) == pack["sha256"]


def test_newest_version_wins(tmp_path: Path) -> None:
    root = _root_with_fixture_packs(tmp_path)
    old = root / "packs" / "en-en-20260101.1.sqlite"
    # Копии с другими версиями: подменяем meta и имя файла.
    for version in ("20260101.10", "20251231"):
        new = root / "packs" / f"en-en-{version}.sqlite"
        shutil.copy(old, new)
        con = sqlite3.connect(new)
        con.execute("UPDATE meta SET value = ? WHERE key = 'version'", (version,))
        con.commit()
        con.close()
    doc = json.loads(manifest.write_root_manifest(root).read_text(encoding="utf-8"))
    en_en = [p for p in doc["packs"] if p["id"] == "en-en"]
    assert [p["version"] for p in en_en] == ["20260101.10"]


def test_filename_must_match_meta(tmp_path: Path) -> None:
    root = _root_with_fixture_packs(tmp_path)
    src = root / "packs" / "en-en-20260101.1.sqlite"
    src.rename(root / "packs" / "en-en-20260102.sqlite")
    with pytest.raises(manifest.ManifestError, match="не совпадает"):
        manifest.write_root_manifest(root)


def test_not_a_pack_and_empty(tmp_path: Path) -> None:
    (tmp_path / "packs").mkdir()
    with pytest.raises(manifest.ManifestError, match="нет пакетов"):
        manifest.write_root_manifest(tmp_path)
    (tmp_path / "packs" / "en-en-20260101.sqlite").write_bytes(b"not sqlite")
    with pytest.raises(manifest.ManifestError, match="не пакет"):
        manifest.write_root_manifest(tmp_path)


def test_manifest_command(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    root = _root_with_fixture_packs(tmp_path)
    assert manifest.main(["manifest", "--out", str(root)]) == 0
    assert (root / "manifest.json").is_file()
    assert manifest.main(["manifest", "--out", str(tmp_path / "empty")]) == 1
    assert "нет пакетов" in capsys.readouterr().err


def test_build_all_on_fixture_data(tmp_path: Path) -> None:
    args = [
        "all",
        "--out",
        str(tmp_path),
        "--dump",
        str(FIXTURES / "kaikki" / "kaikki-100.jsonl"),
        "--cefrj",
        str(FIXTURES / "cefr" / "cefrj-sample.csv"),
        "--octanove",
        str(FIXTURES / "cefr" / "octanove-sample.csv"),
        "--version",
        "20260301",
        "--levels-version",
        "20260302",
        "--extra-words",
        "20",
    ]
    assert manifest.main(args) == 0
    doc = json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))
    got = {p["id"]: p["version"] for p in doc["packs"]}
    assert got == {"en-en": "20260301", "en-forms": "20260301", "en-levels": "20260302"}
    for pack in doc["packs"]:
        assert pack["path"] == f"packs/{pack['id']}-{pack['version']}.sqlite"
        assert sha256_file(tmp_path / pack["path"]) == pack["sha256"]


def test_build_all_requires_dump(tmp_path: Path) -> None:
    with pytest.raises(SystemExit, match="нет дампа"):
        manifest.main(["all", "--out", str(tmp_path), "--dump", str(tmp_path / "none.jsonl")])
