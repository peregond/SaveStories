from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[1]


def read_version() -> str:
    return (ROOT / "VERSION").read_text(encoding="utf-8").strip()


def check_equal(label: str, actual: str, expected: str, errors: list[str]) -> None:
    if actual != expected:
        errors.append(f"{label}: expected {expected!r}, got {actual!r}")


def plist_short_version(path: Path) -> str:
    root = ElementTree.fromstring(path.read_text(encoding="utf-8"))
    children = list(root.find("dict"))
    for index, node in enumerate(children):
        if node.tag == "key" and node.text == "CFBundleShortVersionString":
            return children[index + 1].text or ""
    return ""


def extract_regex(path: Path, pattern: str) -> str:
    match = re.search(pattern, path.read_text(encoding="utf-8"), re.MULTILINE)
    return match.group(1) if match else ""


def main() -> int:
    expected = read_version()
    errors: list[str] = []

    package_json = json.loads((ROOT / "node_worker/package.json").read_text(encoding="utf-8"))
    package_lock = json.loads((ROOT / "node_worker/package-lock.json").read_text(encoding="utf-8"))

    check_equal("node_worker/package.json version", package_json["version"], expected, errors)
    check_equal("node_worker/package-lock.json version", package_lock["version"], expected, errors)
    check_equal(
        "node_worker/package-lock.json packages[\"\"] version",
        package_lock["packages"][""]["version"],
        expected,
        errors,
    )
    check_equal(
        "packaging/AppBundle/Info.plist CFBundleShortVersionString",
        plist_short_version(ROOT / "packaging/AppBundle/Info.plist"),
        expected,
        errors,
    )
    check_equal(
        "windows_app/savestories_windows/ui_support.py fallback version",
        extract_regex(ROOT / "windows_app/savestories_windows/ui_support.py", r'return "([0-9.]+)"'),
        expected,
        errors,
    )
    check_equal(
        "release_notes/latest.md heading",
        extract_regex(ROOT / "release_notes/latest.md", r"^## SaveStories ([0-9.]+)$"),
        expected,
        errors,
    )
    check_equal(
        "README.md source version",
        extract_regex(ROOT / "README.md", r"версия исходников: `([0-9.]+)`"),
        expected,
        errors,
    )

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"Version consistency check passed for {expected}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
