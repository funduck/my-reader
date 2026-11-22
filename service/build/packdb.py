"""Запись пакетов SQLite и manifest.json по схемам из `build.schema`."""

from __future__ import annotations

import hashlib
import json
import sqlite3
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

from build.schema import (
    DDL_META,
    MANIFEST_VERSION,
    PACK_DDL,
    SCHEMA_VERSION,
    normalize_key,
)


@dataclass(frozen=True)
class SenseRow:
    gloss: str
    tags: tuple[str, ...] = ()
    examples: tuple[str, ...] = ()
    #: Русские переводы, относящиеся именно к этому значению.
    ru: tuple[str, ...] = ()


@dataclass(frozen=True)
class EntryRow:
    lemma: str
    pos: str
    ipa: str | None
    senses: tuple[SenseRow, ...]
    #: Русские переводы всей статьи (без привязки к значению).
    ru: tuple[str, ...] = ()


@dataclass(frozen=True)
class FormRow:
    form: str
    lemma: str
    pos: str
    rank: int


@dataclass(frozen=True)
class LevelRow:
    lemma: str
    pos: str
    cefr: str | None
    zipf: float | None
    estimated: bool = False


@dataclass(frozen=True)
class PackMeta:
    pack_id: str
    version: str
    source: str
    license: str
    extra: dict[str, str] = field(default_factory=dict)


def _open(path: Path, meta: PackMeta) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.unlink(missing_ok=True)
    con = sqlite3.connect(path)
    con.execute("PRAGMA foreign_keys = ON")
    con.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
    con.executescript(DDL_META)
    con.executescript(PACK_DDL[meta.pack_id])
    rows = {
        "pack_id": meta.pack_id,
        "schema_version": str(SCHEMA_VERSION),
        "version": meta.version,
        "source": meta.source,
        "license": meta.license,
        **meta.extra,
    }
    con.executemany("INSERT INTO meta (key, value) VALUES (?, ?)", sorted(rows.items()))
    return con


def _tags_json(tags: tuple[str, ...]) -> str | None:
    return json.dumps(list(tags), ensure_ascii=False) if tags else None


def write_en_en(path: Path, meta: PackMeta, entries: Iterable[EntryRow]) -> None:
    """Пишет en-en. Ранг статьи — порядок среди статей с одним ключом (с нуля)."""
    con = _open(path, meta)
    seen: dict[str, int] = {}
    for entry in entries:
        key = normalize_key(entry.lemma)
        rank = seen.get(key, 0)
        seen[key] = rank + 1
        cur = con.execute(
            "INSERT INTO entries (key, lemma, pos, ipa, rank) VALUES (?, ?, ?, ?, ?)",
            (key, entry.lemma, entry.pos, entry.ipa, rank),
        )
        entry_id = cur.lastrowid
        n_ru = 0
        for idx, sense in enumerate(entry.senses):
            cur = con.execute(
                "INSERT INTO senses (entry_id, idx, gloss, tags) VALUES (?, ?, ?, ?)",
                (entry_id, idx, sense.gloss, _tags_json(sense.tags)),
            )
            sense_id = cur.lastrowid
            for ex_idx, text in enumerate(sense.examples):
                con.execute(
                    "INSERT INTO examples (sense_id, idx, text) VALUES (?, ?, ?)",
                    (sense_id, ex_idx, text),
                )
            for text in sense.ru:
                con.execute(
                    "INSERT INTO translations (entry_id, sense_id, lang, text, idx)"
                    " VALUES (?, ?, 'ru', ?, ?)",
                    (entry_id, sense_id, text, n_ru),
                )
                n_ru += 1
        for text in entry.ru:
            con.execute(
                "INSERT INTO translations (entry_id, sense_id, lang, text, idx)"
                " VALUES (?, NULL, 'ru', ?, ?)",
                (entry_id, text, n_ru),
            )
            n_ru += 1
    con.commit()
    con.close()


def write_en_forms(path: Path, meta: PackMeta, rows: Iterable[FormRow]) -> None:
    con = _open(path, meta)
    con.executemany(
        "INSERT INTO forms (form, lemma, pos, rank) VALUES (?, ?, ?, ?)",
        [(normalize_key(r.form), normalize_key(r.lemma), r.pos, r.rank) for r in rows],
    )
    con.commit()
    con.close()


def write_en_levels(path: Path, meta: PackMeta, rows: Iterable[LevelRow]) -> None:
    con = _open(path, meta)
    con.executemany(
        "INSERT INTO levels (lemma, pos, cefr, zipf, estimated) VALUES (?, ?, ?, ?, ?)",
        [(normalize_key(r.lemma), r.pos, r.cefr, r.zipf, int(r.estimated)) for r in rows],
    )
    con.commit()
    con.close()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def manifest_entry(path: Path, meta: PackMeta) -> dict[str, object]:
    """Запись manifest для готового файла пакета `path`."""
    return {
        "id": meta.pack_id,
        "version": meta.version,
        "schema_version": SCHEMA_VERSION,
        "size": path.stat().st_size,
        "sha256": sha256_file(path),
        "path": f"packs/{meta.pack_id}-{meta.version}.sqlite",
        "license": meta.license,
    }


def write_manifest(path: Path, entries: list[dict[str, object]], generated_at: str) -> None:
    doc = {
        "manifest_version": MANIFEST_VERSION,
        "generated_at": generated_at,
        "packs": sorted(entries, key=lambda e: str(e["id"])),
    }
    path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
