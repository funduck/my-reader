"""Тесты build.kaikki: парсер на фрагменте дампа и загрузка с докачкой на подменённом HTTP."""

from __future__ import annotations

import io
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request

import pytest

from build import kaikki
from build.kaikki import Entry, ParseStats, fetch, iter_entries, parse_entry, read_entries

SAMPLE = Path(__file__).resolve().parent.parent / "fixtures" / "kaikki" / "kaikki-100.jsonl"


# ---------------------------------------------------------------- парсер


def test_sample_has_100_entries() -> None:
    stats = ParseStats()
    entries = list(read_entries(SAMPLE, stats))
    assert len(entries) == 100
    assert stats.entries == 100
    assert stats.malformed == 0
    assert stats.skipped_lang == 0
    assert stats.lines == 100


def test_sample_first_entry_fields() -> None:
    first = next(read_entries(SAMPLE))
    assert first.word == "dictionary"
    assert first.pos == "noun"
    assert first.senses[0].glosses[0].startswith("A reference work")
    assert first.senses[0].examples[0] == (
        "If you want to know the meaning of a word, look it up in the dictionary."
    )
    assert any(s.ipa == "/ˈdɪk.ʃə.nə.ɹi/" for s in first.sounds)
    assert first.sounds[0].tags == ("Received-Pronunciation",)
    assert kaikki.Form("dictionaries", ("plural",)) in first.forms


def test_sample_fields_are_typed() -> None:
    for e in read_entries(SAMPLE):
        assert e.word and e.pos
        assert all(isinstance(s.ipa, str) and s.ipa for s in e.sounds)
        assert all(isinstance(f.form, str) and f.form for f in e.forms)
        for s in e.senses:
            assert all(isinstance(g, str) for g in s.glosses)
            assert all(isinstance(x, str) and x for x in s.examples)


def test_missing_optional_fields() -> None:
    e = parse_entry({"word": "x", "pos": "noun"})
    assert e == Entry(word="x", pos="noun")


def test_odd_fields_are_ignored() -> None:
    e = parse_entry(
        {
            "word": "x",
            "pos": "verb",
            "senses": [
                "junk",
                {"glosses": "not a list", "examples": [1, {"text": 5}, {"text": "ok"}, "s"]},
                {"glosses": ["g", 3, ""]},
            ],
            "sounds": [{"audio": "a.ogg"}, {"ipa": "/x/", "tags": "bad"}, None],
            "forms": [{"tags": ["plural"]}, {"form": "xs", "tags": ["plural", 1]}, []],
        }
    )
    assert e is not None
    assert [(s.glosses, s.examples) for s in e.senses] == [
        ((), ("ok",)),
        (("g",), ()),
    ]
    assert e.sounds == (kaikki.Sound("/x/"),)
    assert e.forms == (kaikki.Form("xs", ("plural",)),)


@pytest.mark.parametrize(
    "obj",
    [None, [], "s", 1, {}, {"word": "x"}, {"pos": "noun"}, {"word": "", "pos": "noun"},
     {"word": 1, "pos": "noun"}],
)  # fmt: skip
def test_parse_entry_rejects(obj: object) -> None:
    assert parse_entry(obj) is None


def test_malformed_lines_are_counted_and_skipped() -> None:
    good = json.dumps({"word": "a", "pos": "noun", "lang_code": "en"})
    lines = [
        good,
        "{not json",
        "",
        "   \n",
        "[1, 2]",
        json.dumps({"word": "b"}),
        json.dumps({"word": "c", "pos": "noun", "lang_code": "ru"}),
        json.dumps({"word": "d", "pos": "noun"}),  # без lang_code принимается
        b"\xff\xfe broken utf-8",
        good,
    ]
    stats = ParseStats()
    words = [e.word for e in iter_entries(lines, stats)]
    assert words == ["a", "d", "a"]
    assert stats.entries == 3
    assert stats.malformed == 4
    assert stats.skipped_lang == 1
    assert stats.blank == 2
    assert stats.errors == [2, 5, 6, 9]


def test_parser_is_streaming() -> None:
    consumed = 0

    def gen():
        nonlocal consumed
        for i in range(1000):
            consumed += 1
            yield json.dumps({"word": f"w{i}", "pos": "noun"})

    it = iter_entries(gen())
    assert next(it).word == "w0"
    assert consumed == 1


def test_count_cli(capsys: pytest.CaptureFixture[str]) -> None:
    assert kaikki.main(["count", str(SAMPLE), "--strict"]) == 0
    assert "записей: 100" in capsys.readouterr().out


def test_count_cli_strict_fails_on_bad_lines(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    p = tmp_path / "d.jsonl"
    p.write_text('{"word": "a", "pos": "noun"}\n{"word": "b", "po')
    assert kaikki.main(["count", str(p)]) == 0
    assert kaikki.main(["count", str(p), "--strict"]) == 1
    assert "записей: 1" in capsys.readouterr().out


# ---------------------------------------------------------------- загрузка

URL = "https://example.invalid/dump.jsonl"
LM = "Tue, 04 Nov 2025 10:20:30 GMT"


class FakeResponse:
    def __init__(self, status: int, headers: dict[str, str], body: bytes) -> None:
        self.status = status
        self.headers = headers
        self._body = io.BytesIO(body)

    def read(self, n: int = -1) -> bytes:
        return self._body.read(n)

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *exc: object) -> None:
        return None


class FakeServer:
    """Минимальный HTTP-сервер: HEAD, GET, Range, If-Range. Без сети."""

    def __init__(self, body: bytes, last_modified: str = LM, ranges: bool = True) -> None:
        self.body = body
        self.last_modified = last_modified
        self.ranges = ranges
        self.requests: list[Request] = []
        self.break_after: int | None = None  # оборвать тело GET после стольких байт

    def __call__(self, req: Request) -> FakeResponse:
        self.requests.append(req)
        headers = {"Last-Modified": self.last_modified, "Content-Length": str(len(self.body))}
        if req.get_method() == "HEAD":
            return FakeResponse(200, headers, b"")
        rng = req.get_header("Range")
        if rng and self.ranges and req.get_header("If-range") in (None, self.last_modified):
            start = int(rng.removeprefix("bytes=").removesuffix("-"))
            if start >= len(self.body):
                raise HTTPError(req.full_url, 416, "Range Not Satisfiable", {}, None)  # type: ignore[arg-type]
            part = self.body[start:]
            headers = {"Content-Length": str(len(part))}
            return FakeResponse(206, headers, self._cut(part))
        return FakeResponse(200, headers, self._cut(self.body))

    def _cut(self, data: bytes) -> bytes:
        return data if self.break_after is None else data[: self.break_after]

    def gets(self) -> list[Request]:
        return [r for r in self.requests if r.get_method() == "GET"]


BODY = b'{"word": "a", "pos": "noun"}\n' * 50


def quiet(_: str) -> None:
    return None


def test_fetch_downloads_and_records_version(tmp_path: Path) -> None:
    server = FakeServer(BODY)
    dump = fetch(tmp_path, URL, server, quiet)
    assert dump.read_bytes() == BODY
    assert kaikki.read_version(dump) == "20251104"
    assert (tmp_path / "kaikki.org-dictionary-English.jsonl.version").read_text() == "20251104\n"
    assert not list(tmp_path.glob("*.part*"))
    assert (tmp_path / ".gitignore").read_text() == "*\n"
    assert server.gets()[0].get_header("Range") is None


def test_fetch_skips_when_version_is_current(tmp_path: Path) -> None:
    server = FakeServer(BODY)
    fetch(tmp_path, URL, server, quiet)
    server.requests.clear()
    fetch(tmp_path, URL, server, quiet)
    assert server.gets() == []


def test_fetch_redownloads_new_version(tmp_path: Path) -> None:
    fetch(tmp_path, URL, FakeServer(BODY), quiet)
    new = FakeServer(BODY + b'{"word": "z", "pos": "noun"}\n', "Mon, 01 Dec 2025 00:00:00 GMT")
    dump = fetch(tmp_path, URL, new, quiet)
    assert dump.read_bytes() == new.body
    assert kaikki.read_version(dump) == "20251201"


def test_fetch_resumes_with_range(tmp_path: Path) -> None:
    server = FakeServer(BODY)
    server.break_after = 100
    with pytest.raises(RuntimeError):  # оборванная загрузка: файла нет, .part остался
        fetch(tmp_path, URL, server, quiet)
    part = tmp_path / "kaikki.org-dictionary-English.jsonl.part"
    assert part.stat().st_size == 100
    assert not (tmp_path / "kaikki.org-dictionary-English.jsonl").exists()

    server.break_after = None
    server.requests.clear()
    dump = fetch(tmp_path, URL, server, quiet)
    assert server.gets()[0].get_header("Range") == "bytes=100-"
    assert dump.read_bytes() == BODY
    assert not part.exists()


def test_fetch_restarts_if_server_ignores_range(tmp_path: Path) -> None:
    server = FakeServer(BODY, ranges=False)
    server.break_after = 100
    with pytest.raises(RuntimeError):
        fetch(tmp_path, URL, server, quiet)
    server.break_after = None
    dump = fetch(tmp_path, URL, server, quiet)
    assert dump.read_bytes() == BODY


def test_fetch_restarts_if_dump_changed_during_pause(tmp_path: Path) -> None:
    old = FakeServer(BODY)
    old.break_after = 100
    with pytest.raises(RuntimeError):
        fetch(tmp_path, URL, old, quiet)
    new = FakeServer(b'{"word": "n", "pos": "noun"}\n' * 70, "Mon, 01 Dec 2025 00:00:00 GMT")
    dump = fetch(tmp_path, URL, new, quiet)
    assert dump.read_bytes() == new.body
    assert new.gets()[0].get_header("Range") is None  # метка не совпала: с нуля


def test_fetch_finishes_complete_part_via_416(tmp_path: Path) -> None:
    server = FakeServer(BODY)
    server.break_after = len(BODY)  # тело отдано целиком, но rename не случился
    part = tmp_path / "kaikki.org-dictionary-English.jsonl.part"
    (tmp_path / "kaikki.org-dictionary-English.jsonl.part.lm").write_text(LM)
    part.write_bytes(BODY)
    dump = fetch(tmp_path, URL, server, quiet)
    assert dump.read_bytes() == BODY


def test_fetch_requires_last_modified(tmp_path: Path) -> None:
    def opener(req: Request) -> FakeResponse:
        return FakeResponse(200, {}, b"")

    with pytest.raises(RuntimeError, match="Last-Modified"):
        fetch(tmp_path, URL, opener, quiet)
