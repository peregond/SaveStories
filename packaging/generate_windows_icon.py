#!/usr/bin/env python3

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path


LIME = (191, 255, 0, 255)
ICO_SIZES = [16, 32, 48, 64, 128, 256]


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
        raise SystemExit("usage: generate_windows_icon.py <output.ico>")

    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)

    images = [solid_png(size, LIME) for size in ICO_SIZES]
    header = struct.pack("<HHH", 0, 1, len(images))
    directory = bytearray()
    offset = 6 + 16 * len(images)

    for size, image in zip(ICO_SIZES, images):
        width = 0 if size >= 256 else size
        height = 0 if size >= 256 else size
        directory.extend(
            struct.pack(
                "<BBBBHHII",
                width,
                height,
                0,
                0,
                1,
                32,
                len(image),
                offset,
            )
        )
        offset += len(image)

    output.write_bytes(header + directory + b"".join(images))


if __name__ == "__main__":
    main()
