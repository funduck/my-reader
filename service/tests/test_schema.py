from pathlib import Path

import pytest

from build import schema

DOC = Path(__file__).resolve().parents[2] / "docs" / "Architecture-service.md"


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("Went", "went"),
        ("  Take   OFF ", "take off"),
        ("can’t", "can't"),
        ("Mother-in-Law", "mother-in-law"),
        ("a\tb\nc", "a b c"),
        ("‘Hello’", "'hello'"),
        ("", ""),
    ],
)
def test_normalize_key(text: str, expected: str) -> None:
    assert schema.normalize_key(text) == expected


def test_normalize_key_idempotent() -> None:
    once = schema.normalize_key("  Don’t   Stop ")
    assert schema.normalize_key(once) == once


@pytest.mark.parametrize("name", ["DDL_META", "DDL_EN_EN", "DDL_EN_FORMS", "DDL_EN_LEVELS"])
def test_doc_contains_exact_ddl(name: str) -> None:
    """DDL в документе дословно совпадает с кодом: документ — контракт."""
    doc = DOC.read_text(encoding="utf-8")
    assert getattr(schema, name) in doc


def test_doc_has_schema_section() -> None:
    assert "## 4. Схемы пакетов" in DOC.read_text(encoding="utf-8")


@pytest.mark.parametrize("version", ["20260101", "20260101.1", "20260101.12"])
def test_version_ok(version: str) -> None:
    assert schema.VERSION_RE.match(version)


@pytest.mark.parametrize("version", ["2026-01-01", "1.0.0", "20260101.", "v20260101"])
def test_version_bad(version: str) -> None:
    assert not schema.VERSION_RE.match(version)
