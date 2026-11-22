"""Сборка всех пакетов и ``manifest.json`` (T-036).

Раскладка корня сервиса (по умолчанию ``data/out/``)::

    manifest.json
    packs/<id>-<version>.sqlite

Команды::

    python -m build.manifest all        # собрать en-en, en-forms, en-levels и manifest.json
    python -m build.manifest manifest   # только переписать manifest.json по packs/

Версии: ``en-en`` и ``en-forms`` берут версию дампа kaikki.org (файл ``.version``
рядом с дампом, ``--version`` переопределяет); ``en-levels`` не зависит от дампа и
получает свою версию (``--levels-version``, по умолчанию сегодняшняя дата ``ГГГГММДД``).

Формат манифеста — как в ``fixtures/manifest.json`` (``build.packdb.manifest_entry``).
Манифест строится по файлам: id, версия и лицензия читаются из таблицы ``meta`` самого
пакета, размер и sha256 считаются по файлу. Если в ``packs/`` лежит несколько версий
одного id, в манифест попадает новейшая; остальные файлы не трогаются.
"""

from __future__ import annotations

import argparse
import datetime as dt
import sqlite3
import sys
from pathlib import Path

from build import kaikki, pack_en_en, pack_en_forms, pack_en_levels
from build.packdb import PackMeta, manifest_entry, write_manifest
from build.schema import PACK_DDL, VERSION_RE

DEFAULT_OUT_ROOT = kaikki.DATA_DIR / "out"
MANIFEST_NAME = "manifest.json"
PACKS_DIR = "packs"


class ManifestError(ValueError):
    """Файл пакета не годится для манифеста."""


def read_pack_meta(path: Path) -> PackMeta:
    """Читает ``meta`` пакета; имя файла должно быть ``<id>-<version>.sqlite`` из ``meta``."""
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        meta = dict(con.execute("SELECT key, value FROM meta"))
    except sqlite3.DatabaseError as e:
        raise ManifestError(f"{path}: не пакет ({e})") from e
    finally:
        con.close()
    missing = {"pack_id", "version", "source", "license"} - set(meta)
    if missing:
        raise ManifestError(f"{path}: в meta нет {sorted(missing)}")
    pack = PackMeta(meta["pack_id"], meta["version"], meta["source"], meta["license"])
    if pack.pack_id not in PACK_DDL:
        raise ManifestError(f"{path}: неизвестный pack_id {pack.pack_id!r}")
    if not VERSION_RE.match(pack.version):
        raise ManifestError(f"{path}: версия {pack.version!r} не ГГГГММДД[.N]")
    if path.name != f"{pack.pack_id}-{pack.version}.sqlite":
        raise ManifestError(
            f"{path}: имя файла не совпадает с meta ({pack.pack_id}-{pack.version})"
        )
    return pack


def _version_key(version: str) -> tuple[int, int]:
    day, _, n = version.partition(".")
    return int(day), int(n or 0)


def collect_entries(root: Path) -> list[dict[str, object]]:
    """Записи манифеста для новейших пакетов в ``root/packs/``."""
    newest: dict[str, tuple[Path, PackMeta]] = {}
    for path in sorted((root / PACKS_DIR).glob("*.sqlite")):
        meta = read_pack_meta(path)
        best = newest.get(meta.pack_id)
        if best is None or _version_key(meta.version) > _version_key(best[1].version):
            newest[meta.pack_id] = (path, meta)
    return [manifest_entry(path, meta) for path, meta in newest.values()]


def _now() -> str:
    return dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_root_manifest(root: Path, generated_at: str | None = None) -> Path:
    """Пишет ``root/manifest.json`` по пакетам в ``root/packs/``; возвращает путь к нему."""
    entries = collect_entries(root)
    if not entries:
        raise ManifestError(f"нет пакетов в {root / PACKS_DIR}")
    out = root / MANIFEST_NAME
    write_manifest(out, entries, generated_at or _now())
    return out


def build_all(args: argparse.Namespace) -> Path:
    """Собирает три пакета в ``out/packs/`` и пишет манифест."""
    packs = args.out / PACKS_DIR
    if not args.dump.exists():
        raise SystemExit(f"нет дампа {args.dump}: python -m build.kaikki fetch")
    version = args.version or kaikki.read_version(args.dump)
    if not version:
        raise SystemExit(f"нет версии дампа ({kaikki.version_path(args.dump)}): задайте --version")
    for csv in (args.cefrj, args.octanove):
        if not csv.exists():
            raise SystemExit(f"нет {csv}: python -m build.pack_en_levels fetch")

    out, stats, applied = pack_en_en.build_auto(args.dump, packs, version, args.min_zipf)
    print(f"{out}: статей {stats.kept}, {out.stat().st_size} байт, порог Zipf: {applied or 'нет'}")
    forms = packs / f"en-forms-{version}.sqlite"
    rows = pack_en_forms.build_pack(args.dump, forms, version)
    print(f"{forms}: {len(rows)} строк, {forms.stat().st_size} байт")
    levels = packs / f"en-levels-{args.levels_version}.sqlite"
    lrows = pack_en_levels.build_pack(
        args.cefrj, args.octanove, levels, args.levels_version, args.extra_words
    )
    print(f"{levels}: {len(lrows)} строк, {levels.stat().st_size} байт")
    return write_root_manifest(args.out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="build.manifest", description="Пакеты и manifest.json")
    sub = parser.add_subparsers(dest="cmd", required=True)
    cefr_dir = pack_en_levels.DEFAULT_CEFR_DIR
    a = sub.add_parser("all", help="собрать все пакеты и manifest.json")
    a.add_argument("--out", type=Path, default=DEFAULT_OUT_ROOT, help="корень сервиса")
    a.add_argument("--dump", type=Path, default=kaikki.DATA_DIR / kaikki.DUMP_NAME)
    a.add_argument("--cefrj", type=Path, default=cefr_dir / pack_en_levels.CEFRJ_NAME)
    a.add_argument("--octanove", type=Path, default=cefr_dir / pack_en_levels.OCTANOVE_NAME)
    a.add_argument("--version", help="версия en-en и en-forms; по умолчанию версия дампа")
    a.add_argument("--levels-version", default=pack_en_levels._version_today())
    a.add_argument("--min-zipf", type=float, default=None, help="как у build.pack_en_en")
    a.add_argument("--extra-words", type=int, default=50_000)
    m = sub.add_parser("manifest", help="переписать manifest.json по готовым packs/")
    m.add_argument("--out", type=Path, default=DEFAULT_OUT_ROOT, help="корень сервиса")
    args = parser.parse_args(argv)

    try:
        path = build_all(args) if args.cmd == "all" else write_root_manifest(args.out)
    except ManifestError as e:
        print(f"ошибка: {e}", file=sys.stderr)
        return 1
    print(f"манифест: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
