"""T-036: HTTP-раздача, в процессе pytest на свободном порту 127.0.0.1."""

from __future__ import annotations

import http.client
import json
import shutil
import threading
from collections.abc import Iterator
from pathlib import Path

import pytest

from build import manifest
from serve.server import make_server, parse_range

FIXTURES = Path(__file__).resolve().parent.parent / "fixtures"
PACK = "packs/en-forms-20260101.1.sqlite"


@pytest.fixture
def root(tmp_path: Path) -> Path:
    """Корень раздачи ``tmp/root``; рядом, снаружи, лежит ``secret.txt``."""
    (tmp_path / "secret.txt").write_text("outside")
    served = tmp_path / "root"
    shutil.copytree(FIXTURES / "packs", served / "packs")
    manifest.write_root_manifest(served)
    return served


@pytest.fixture
def port(root: Path) -> Iterator[int]:
    server = make_server(root, "127.0.0.1", 0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server.server_address[1]
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def _req(
    port: int, path: str, method: str = "GET", headers: dict[str, str] | None = None
) -> tuple[int, dict[str, str], bytes]:
    con = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        con.request(method, path, headers=headers or {})
        resp = con.getresponse()
        return resp.status, dict(resp.getheaders()), resp.read()
    finally:
        con.close()


def test_manifest(port: int, root: Path) -> None:
    status, headers, body = _req(port, "/manifest.json")
    assert status == 200
    assert headers["Content-Type"] == "application/json"
    assert int(headers["Content-Length"]) == len(body)
    assert body == (root / "manifest.json").read_bytes()
    assert [p["id"] for p in json.loads(body)["packs"]] == ["en-en", "en-forms", "en-levels"]


def test_pack_bytes_exact(port: int, root: Path) -> None:
    status, headers, body = _req(port, "/" + PACK)
    assert status == 200
    assert body == (root / PACK).read_bytes()
    assert headers["Accept-Ranges"] == "bytes"
    assert int(headers["Content-Length"]) == len(body)


def test_head(port: int, root: Path) -> None:
    status, headers, body = _req(port, "/" + PACK, "HEAD")
    assert status == 200
    assert body == b""
    assert int(headers["Content-Length"]) == (root / PACK).stat().st_size


@pytest.mark.parametrize(
    "path", ["/nope.json", "/packs/", "/packs", "/../secret.txt", "/%2e%2e/secret.txt"]
)
def test_404(port: int, path: str) -> None:
    assert _req(port, path)[0] == 404


def test_range_bounded_open_and_suffix(port: int, root: Path) -> None:
    data = (root / PACK).read_bytes()
    size = len(data)
    cases = {
        "bytes=0-99": (data[0:100], f"bytes 0-99/{size}"),
        "bytes=100-": (data[100:], f"bytes 100-{size - 1}/{size}"),
        "bytes=-50": (data[-50:], f"bytes {size - 50}-{size - 1}/{size}"),
    }
    for header, (want, content_range) in cases.items():
        status, headers, body = _req(port, "/" + PACK, headers={"Range": header})
        assert status == 206, header
        assert body == want, header
        assert headers["Content-Range"] == content_range, header
        assert int(headers["Content-Length"]) == len(want), header


def test_range_resume_reassembles_file(port: int, root: Path) -> None:
    data = (root / PACK).read_bytes()
    part = _req(port, "/" + PACK, headers={"Range": "bytes=0-999"})[2]
    rest = _req(port, "/" + PACK, headers={"Range": f"bytes={len(part)}-"})[2]
    assert part + rest == data


def test_range_unsatisfiable(port: int, root: Path) -> None:
    size = (root / PACK).stat().st_size
    status, headers, _ = _req(port, "/" + PACK, headers={"Range": f"bytes={size}-"})
    assert status == 416
    assert headers["Content-Range"] == f"bytes */{size}"


def test_multi_range_ignored(port: int, root: Path) -> None:
    status, _, body = _req(port, "/" + PACK, headers={"Range": "bytes=0-1,5-6"})
    assert status == 200
    assert body == (root / PACK).read_bytes()


def test_parse_range() -> None:
    assert parse_range("bytes=0-9", 100) == (0, 9)
    assert parse_range("bytes=90-200", 100) == (90, 99)
    assert parse_range("bytes=-500", 100) == (0, 99)
    assert parse_range("bytes=5-2", 100) == "invalid"
    assert parse_range("bytes=-0", 100) == "invalid"
    assert parse_range("items=0-1", 100) is None
    assert parse_range("bytes=-", 100) is None


def test_cli_requires_manifest(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    from serve.__main__ import main

    assert main(["--dir", str(tmp_path)]) == 1
    assert "manifest.json" in capsys.readouterr().err
