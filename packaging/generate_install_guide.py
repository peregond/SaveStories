#!/usr/bin/env python3

from __future__ import annotations

import html
import sys
from pathlib import Path


TITLE = "Как установить DimaSave"
STEPS = [
    "1. Откройте DimaSave.dmg.",
    "2. Перетащите DimaSave.app в Applications.",
    "3. Запустите приложение из Applications.",
    "4. Если macOS покажет предупреждение, нажмите Right Click -> Open.",
    "5. Если появится сообщение «приложение повреждено», выполните в Terminal:",
    "   xattr -dr com.apple.quarantine /Applications/DimaSave.app",
    "6. Внутри приложения откройте шестерёнку и выполните вход в Instagram.",
]
FOOTER = "Сборка без Developer ID и notarization, поэтому Gatekeeper может запросить ручное подтверждение."


def build_svg() -> str:
    escaped_steps = "".join(
        f'<text x="72" y="{190 + index * 74}" font-size="31" font-weight="600" fill="#101418">{html.escape(step)}</text>'
        for index, step in enumerate(STEPS)
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="980" viewBox="0 0 1400 980">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#f5f1df"/>
      <stop offset="55%" stop-color="#dce7ef"/>
      <stop offset="100%" stop-color="#d5e5de"/>
    </linearGradient>
  </defs>
  <rect width="1400" height="980" fill="url(#bg)"/>
  <rect x="42" y="42" width="1316" height="896" rx="36" fill="#ffffff" fill-opacity="0.74"/>
  <rect x="72" y="86" width="116" height="116" rx="28" fill="#bfff00"/>
  <text x="228" y="136" font-size="56" font-weight="700" fill="#101418">{html.escape(TITLE)}</text>
  <text x="228" y="188" font-size="26" font-weight="500" fill="#50606d">Быстрые шаги для первого запуска на другом Mac</text>
  {escaped_steps}
  <rect x="72" y="800" width="1256" height="104" rx="26" fill="#101418" fill-opacity="0.90"/>
  <text x="106" y="864" font-size="28" font-weight="600" fill="#f4f7f8">{html.escape(FOOTER)}</text>
</svg>
"""


def build_text() -> str:
    lines = [TITLE, "", *STEPS, "", FOOTER, ""]
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_install_guide.py <output-dir>")

    output_dir = Path(sys.argv[1])
    output_dir.mkdir(parents=True, exist_ok=True)

    (output_dir / "How to Install DimaSave.svg").write_text(build_svg(), encoding="utf-8")
    (output_dir / "How to Install DimaSave.txt").write_text(build_text(), encoding="utf-8")


if __name__ == "__main__":
    main()
