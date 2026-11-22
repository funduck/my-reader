"""Раздача корня сервиса по HTTP: ``GET /manifest.json`` и ``GET /packs/<id>-<version>.sqlite``.

Только stdlib. ``GET`` и ``HEAD``, ``Content-Length``, ``Accept-Ranges: bytes`` и один
диапазон ``Range: bytes=a-b | a- | -n`` (ответ 206): по нему приложение докачивает большие
пакеты. Несколько диапазонов в одном заголовке не поддерживаются: отдаётся весь файл (200).
Каталоги не листаются (404), выход за корень (``..``) — 404.
"""

from __future__ import annotations

import re
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

CONTENT_TYPES = {
    ".json": "application/json",
    ".sqlite": "application/octet-stream",
}
_RANGE = re.compile(r"^bytes=(\d*)-(\d*)$")


def parse_range(header: str, size: int) -> tuple[int, int] | None | str:
    """Разбирает ``Range``.

    Возвращает ``(first, last)`` включительно, ``None`` — заголовок игнорировать
    (не ``bytes`` или несколько диапазонов), ``"invalid"`` — не удовлетворим (416).
    """
    m = _RANGE.match(header.strip())
    if not m:
        return None
    first, last = m.groups()
    if not first and not last:
        return None
    if not first:  # суффикс: последние n байт
        n = int(last)
        if n == 0 or size == 0:
            return "invalid"
        return max(size - n, 0), size - 1
    start = int(first)
    end = min(int(last), size - 1) if last else size - 1
    if start >= size or end < start:
        return "invalid"
    return start, end


class PackHandler(BaseHTTPRequestHandler):
    root: Path = Path(".")
    server_version = "my-reader-serve"

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        if getattr(self.server, "verbose", False):
            super().log_message(format, *args)

    def _resolve(self) -> Path | None:
        rel = unquote(urlsplit(self.path).path).lstrip("/")
        target = (self.root / rel).resolve()
        if not target.is_relative_to(self.root.resolve()) or not target.is_file():
            return None
        return target

    def _serve(self, head: bool) -> None:
        target = self._resolve()
        if target is None:
            self.send_error(HTTPStatus.NOT_FOUND, "not found")
            return
        size = target.stat().st_size
        ctype = CONTENT_TYPES.get(target.suffix, "application/octet-stream")
        header = self.headers.get("Range")
        rng = parse_range(header, size) if header else None
        if rng == "invalid":
            self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
            self.send_header("Content-Range", f"bytes */{size}")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        first, last = (0, size - 1) if rng is None else rng
        length = last - first + 1
        self.send_response(HTTPStatus.OK if rng is None else HTTPStatus.PARTIAL_CONTENT)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if rng is not None:
            self.send_header("Content-Range", f"bytes {first}-{last}/{size}")
        self.end_headers()
        if head or length <= 0:
            return
        with target.open("rb") as f:
            f.seek(first)
            remaining = length
            while remaining:
                chunk = f.read(min(1 << 20, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def do_GET(self) -> None:  # noqa: N802
        self._serve(head=False)

    def do_HEAD(self) -> None:  # noqa: N802
        self._serve(head=True)


def make_server(root: Path, host: str = "127.0.0.1", port: int = 8080) -> ThreadingHTTPServer:
    """Создаёт сервер (порт 0 — свободный, см. ``server_address``); запуск — ``serve_forever``."""
    handler = type("Handler", (PackHandler,), {"root": root})
    server = ThreadingHTTPServer((host, port), handler)
    server.daemon_threads = True
    return server
