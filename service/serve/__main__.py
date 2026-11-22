"""``python -m serve [--dir PATH] [--port 8080] [--lan]``: раздача корня сервиса."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from serve.server import make_server

DEFAULT_DIR = Path(__file__).resolve().parent.parent / "data" / "out"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="serve", description="Раздача пакетов по HTTP")
    parser.add_argument(
        "--dir", type=Path, default=DEFAULT_DIR, help="корень: manifest.json, packs/"
    )
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--lan", action="store_true", help="слушать 0.0.0.0 вместо 127.0.0.1")
    args = parser.parse_args(argv)
    manifest = args.dir / "manifest.json"
    if not manifest.is_file():
        print(f"нет {manifest}: сначала python -m build.manifest all", file=sys.stderr)
        return 1
    host = "0.0.0.0" if args.lan else "127.0.0.1"
    server = make_server(args.dir, host, args.port)
    setattr(server, "verbose", True)  # noqa: B010
    print(f"раздаю {args.dir} на http://{host}:{args.port}/ (Ctrl+C - стоп)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
