#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path


SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg width="1000" height="640" viewBox="0 0 1000 640" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1000" y2="640" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F4FFD3"/>
      <stop offset="0.45" stop-color="#E6FFB1"/>
      <stop offset="1" stop-color="#CFF46A"/>
    </linearGradient>
    <radialGradient id="limeMist" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(820 140) rotate(140) scale(340 300)">
      <stop stop-color="#F8FFD8" stop-opacity="0.78"/>
      <stop offset="1" stop-color="#F8FFD8" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glassBloom" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(260 120) rotate(35) scale(420 240)">
      <stop stop-color="white" stop-opacity="0.34"/>
      <stop offset="1" stop-color="white" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <rect width="1000" height="640" rx="30" fill="url(#bg)"/>
  <rect width="1000" height="640" rx="30" fill="url(#limeMist)"/>
  <rect width="1000" height="640" rx="30" fill="url(#glassBloom)"/>
</svg>
"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: generate_dmg_background.py <output.svg>")

    output = Path(sys.argv[1]).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(SVG, encoding="utf-8")


if __name__ == "__main__":
    main()
