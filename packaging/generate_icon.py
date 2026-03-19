#!/usr/bin/env python3

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path


LIME = (191, 255, 0, 255)
ICON_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
    "icon_1024x1024.png": 1024,
}


def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + chunk_type
        + data
        + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    )


def solid_png(size: int, rgba: tuple[int, int, int, int]) -> bytes:
    row = bytes(rgba) * size
    raw = b"".join(b"\x00" + row for _ in range(size))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            png_chunk(b"IHDR", ihdr),
            png_chunk(b"IDAT", zlib.compress(raw, level=9)),
            png_chunk(b"IEND", b""),
        ]
    )


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_icon.py <iconset-dir>")

    target = Path(sys.argv[1])
    target.mkdir(parents=True, exist_ok=True)

    for filename, size in ICON_SIZES.items():
        (target / filename).write_bytes(solid_png(size, LIME))


if __name__ == "__main__":
    main()
