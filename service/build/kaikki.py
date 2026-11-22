"""Дамп английского Wiktionary с kaikki.org: загрузка и потоковое чтение.

Команды (из ``service/``)::

    uv run python -m build.kaikki fetch              # скачать в data/ с докачкой
    uv run python -m build.kaikki count [путь.jsonl] # прочитать дамп, вывести число записей

Только стандартная библиотека. Данные Wiktionary — CC BY-SA, см. fixtures/kaikki/ATTRIBUTION.md.

Плохие строки. Парсер не падает на мусоре: строка, которая не разбирается как JSON-объект,
или запись без ``word``/``pos``, пропускается и считается в ``ParseStats``. Запись с другим
``lang_code`` (не ``en``) тоже пропускается и считается отдельно; запись без ``lang_code``
принимается. Необязательные поля неверного типа считаются пустыми. ``count`` выводит оба
счётчика и с ``--strict`` завершается с кодом 1, если были плохие строки (например, оборванная
докачка оставила половину последней строки).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass, field
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import IO, Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen

DUMP_URL = "https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl"
DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DUMP_NAME = "kaikki.org-dictionary-English.jsonl"
LANG_CODE = "en"
CHUNK = 1 << 20

# ---------------------------------------------------------------- модель


@dataclass(frozen=True, slots=True)
class Sense:
    """Одно значение слова: толкования (``glosses``) и примеры из Wiktionary."""

    glosses: tuple[str, ...] = ()
    examples: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class Sound:
    """Произношение с IPA (записи без IPA, например только аудио, не попадают в модель)."""

    ipa: str
    tags: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class Form:
    """Словоформа леммы (``plural``, ``past``, ...) или вариант написания (``alternative``)."""

    form: str
    tags: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class Entry:
    """Одна строка дампа: слово + часть речи."""

    word: str
    pos: str
    senses: tuple[Sense, ...] = ()
    sounds: tuple[Sound, ...] = ()
    forms: tuple[Form, ...] = ()


@dataclass(slots=True)
class ParseStats:
    """Счётчики потокового чтения."""

    entries: int = 0
    malformed: int = 0  # не JSON-объект или нет word/pos
    skipped_lang: int = 0  # lang_code не "en"
    blank: int = 0  # пустые строки (плохими не считаются)
    errors: list[int] = field(default_factory=list)  # номера первых 10 плохих строк

    @property
    def lines(self) -> int:
        return self.entries + self.malformed + self.skipped_lang + self.blank


# ---------------------------------------------------------------- разбор


def _str_tuple(value: Any) -> tuple[str, ...]:
    if not isinstance(value, list):
        return ()
    return tuple(v for v in value if isinstance(v, str) and v)


def _dicts(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, list):
        for v in value:
            if isinstance(v, dict):
                yield v


def _sense(raw: dict[str, Any]) -> Sense:
    examples = tuple(
        t for ex in _dicts(raw.get("examples")) if isinstance(t := ex.get("text"), str) and t
    )
    return Sense(glosses=_str_tuple(raw.get("glosses")), examples=examples)


def parse_entry(obj: Any) -> Entry | None:
    """Строит ``Entry`` из разобранного JSON. ``None`` — не объект или нет ``word``/``pos``."""
    if not isinstance(obj, dict):
        return None
    word, pos = obj.get("word"), obj.get("pos")
    if not (isinstance(word, str) and word and isinstance(pos, str) and pos):
        return None
    sounds = tuple(
        Sound(ipa=ipa, tags=_str_tuple(s.get("tags")))
        for s in _dicts(obj.get("sounds"))
        if isinstance(ipa := s.get("ipa"), str) and ipa
    )
    forms = tuple(
        Form(form=f, tags=_str_tuple(d.get("tags")))
        for d in _dicts(obj.get("forms"))
        if isinstance(f := d.get("form"), str) and f
    )
    return Entry(
        word=word,
        pos=pos,
        senses=tuple(_sense(s) for s in _dicts(obj.get("senses"))),
        sounds=sounds,
        forms=forms,
    )


def iter_entries(lines: Iterable[str | bytes], stats: ParseStats | None = None) -> Iterator[Entry]:
    """Потоково разбирает строки JSONL; в памяти держит одну запись."""
    stats = stats if stats is not None else ParseStats()
    for n, line in enumerate(lines, start=1):
        if not line.strip():
            stats.blank += 1
            continue
        try:
            obj = json.loads(line)
        except ValueError:  # JSONDecodeError и UnicodeDecodeError
            obj = None
        if isinstance(obj, dict):
            code = obj.get("lang_code")
            if code is not None and code != LANG_CODE:
                stats.skipped_lang += 1
                continue
        entry = parse_entry(obj)
        if entry is None:
            stats.malformed += 1
            if len(stats.errors) < 10:
                stats.errors.append(n)
            continue
        stats.entries += 1
        yield entry


def read_entries(path: Path, stats: ParseStats | None = None) -> Iterator[Entry]:
    """``iter_entries`` по файлу; открывает его в двоичном режиме и сам закрывает."""
    with path.open("rb") as f:
        yield from iter_entries(f, stats)


# ---------------------------------------------------------------- загрузка

Opener = Callable[[Request], Any]
"""Как ``urllib.request.urlopen``: принимает ``Request``, возвращает контекстный менеджер
с ``status``, ``headers`` и ``read(n)``; на ошибку HTTP бросает ``HTTPError``."""


def _version_from(last_modified: str) -> str:
    """``Last-Modified`` (RFC 7231) -> ``YYYYMMDD``."""
    return parsedate_to_datetime(last_modified).strftime("%Y%m%d")


def version_path(dump: Path) -> Path:
    """Файл с версией рядом с дампом."""
    return dump.with_name(dump.name + ".version")


def read_version(dump: Path) -> str | None:
    """Версия скачанного дампа (дата ``YYYYMMDD``) или ``None``."""
    p = version_path(dump)
    return p.read_text().strip() if p.exists() else None


def fetch(
    dest_dir: Path = DATA_DIR,
    url: str = DUMP_URL,
    opener: Opener = urlopen,
    log: Callable[[str], None] = print,
) -> Path:
    """Скачивает дамп в ``dest_dir`` с докачкой; пишет версию рядом (``<имя>.version``).

    Версия — дата ``Last-Modified`` сервера, ``YYYYMMDD``. Если на диске уже лежит дамп той же
    версии, ничего не качает. Недокачанное хранится в ``<имя>.part`` (+ ``.part.lm`` с
    ``Last-Modified``, при докачке уходит в ``If-Range``): если файл на сервере сменился,
    сервер отдаёт 200 и загрузка начинается заново. Готовый файл появляется атомарным rename.
    В ``dest_dir`` кладётся ``.gitignore`` с ``*``: дампы не попадают в репозиторий.
    """
    dest_dir.mkdir(parents=True, exist_ok=True)
    ignore = dest_dir / ".gitignore"
    if not ignore.exists():
        ignore.write_text("*\n")
    dump = dest_dir / DUMP_NAME
    part = dump.with_name(dump.name + ".part")
    part_lm = dump.with_name(dump.name + ".part.lm")

    with opener(Request(url, method="HEAD")) as head:
        last_modified = head.headers.get("Last-Modified")
        total = head.headers.get("Content-Length")
    if not last_modified:
        raise RuntimeError("сервер не прислал Last-Modified: версию дампа определить нечем")
    version = _version_from(last_modified)

    if dump.exists() and read_version(dump) == version:
        log(f"уже скачан: {dump} (версия {version})")
        return dump

    offset = part.stat().st_size if part.exists() else 0
    if offset and (not part_lm.exists() or part_lm.read_text() != last_modified):
        offset = 0  # докачивать нечего: другая версия или нет метки
    if total is not None and offset > int(total):
        offset = 0

    headers = {}
    if offset:
        headers = {"Range": f"bytes={offset}-", "If-Range": last_modified}
    complete = total is not None and offset == int(total)
    if not complete:
        try:
            resp_cm = opener(Request(url, headers=headers))
        except HTTPError as e:
            if e.code != 416:
                raise
            complete = True  # диапазон за концом файла: .part уже целый
        else:
            with resp_cm as resp:
                if offset and resp.status != 206:
                    offset = 0  # сервер игнорирует Range или файл сменился: качаем заново
                log(f"качаю {url} с байта {offset}")
                part_lm.write_text(last_modified)
                with part.open("ab" if offset else "wb") as out:
                    _copy(resp, out)
    size = part.stat().st_size
    if total is not None and size != int(total):
        raise RuntimeError(f"загружено {size} байт из {total}: запустите fetch ещё раз")
    os.replace(part, dump)
    version_path(dump).write_text(version + "\n")
    part_lm.unlink(missing_ok=True)
    log(f"готово: {dump} (версия {version}, {size} байт)")
    return dump


def _copy(resp: Any, out: IO[bytes]) -> None:
    while chunk := resp.read(CHUNK):
        out.write(chunk)


# ---------------------------------------------------------------- CLI


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="build.kaikki", description="Дамп kaikki.org")
    sub = parser.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fetch", help="скачать дамп в service/data/ (с докачкой)")
    f.add_argument("--url", default=DUMP_URL)
    f.add_argument("--dest", type=Path, default=DATA_DIR)
    c = sub.add_parser("count", help="прочитать дамп потоком и вывести число записей")
    c.add_argument("path", nargs="?", type=Path, default=DATA_DIR / DUMP_NAME)
    c.add_argument("--strict", action="store_true", help="код 1, если есть плохие строки")
    args = parser.parse_args(argv)

    if args.cmd == "fetch":
        fetch(args.dest, args.url)
        return 0
    stats = ParseStats()
    for _ in read_entries(args.path, stats):
        pass
    print(f"записей: {stats.entries}")
    print(f"плохих строк: {stats.malformed}; чужой язык: {stats.skipped_lang}")
    if stats.errors:
        print(f"первые плохие строки: {stats.errors}", file=sys.stderr)
    return 1 if args.strict and stats.malformed else 0


if __name__ == "__main__":
    sys.exit(main())
