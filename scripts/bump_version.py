#!/usr/bin/env python3
"""Поднимает версию проекта во всех файлах одной командой.

    python3 scripts/bump_version.py 0.6.87

Меняет: VERSION, README.md (версия исходников), node_worker и windows_app_react (package.json и lock),
Cargo.toml и Cargo.lock клиента Windows, tauri.conf.json, Info.plist (macOS), запасную версию в Python-клиенте,
демо-версию интерфейса. Заголовок release_notes/latest.md обновляется тоже, если он ещё со старой версией.
После правок запускается scripts/check_version_consistency.py.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


# Все правки собираются в памяти и записываются только если каждая нашла своё место: при ошибке файлы остаются нетронутыми.
_pending: dict[str, str] = {}


def read(path: str) -> str:
    return _pending[path] if path in _pending else (ROOT / path).read_text(encoding="utf-8")


def stage(path: str, text: str) -> None:
    _pending[path] = text


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if old not in text:
        raise SystemExit(f"{path}: не найдено {old!r}. Ничего не изменено.")
    stage(path, text.replace(old, new, 1))


def bump(new: str) -> None:
    if not re.fullmatch(r"\d+\.\d+\.\d+", new):
        raise SystemExit("Версия должна быть вида X.Y.Z")
    old = read("VERSION").strip()
    if old == new:
        raise SystemExit(f"Версия уже {new}")

    stage("VERSION", new + "\n")
    replace_once("README.md", f"версия исходников: `{old}`", f"версия исходников: `{new}`")
    replace_once("packaging/AppBundle/Info.plist", f"<string>{old}</string>", f"<string>{new}</string>")
    replace_once("windows_app/savestories_windows/ui_support.py", f'return "{old}"', f'return "{new}"')
    replace_once("windows_app_react/src/demoApi.ts", f'version: "{old}"', f'version: "{new}"')
    replace_once("windows_app_react/src-tauri/tauri.conf.json", f'"version": "{old}"', f'"version": "{new}"')
    replace_once("windows_app_react/src-tauri/Cargo.toml", f'version = "{old}"', f'version = "{new}"')
    replace_once("windows_app_react/src-tauri/Cargo.lock", f'name = "saveme-windows"\nversion = "{old}"', f'name = "saveme-windows"\nversion = "{new}"')

    for pkg in ("node_worker/package.json", "windows_app_react/package.json"):
        replace_once(pkg, f'"version": "{old}"', f'"version": "{new}"')
    for lock in ("node_worker/package-lock.json", "windows_app_react/package-lock.json"):
        data = json.loads(read(lock))
        data["version"] = new
        data["packages"][""]["version"] = new
        stage(lock, json.dumps(data, indent=2, ensure_ascii=False) + "\n")

    notes = read("release_notes/latest.md")
    if notes.startswith(f"## SaveMe {old}"):
        stage("release_notes/latest.md", notes.replace(f"## SaveMe {old}", f"## SaveMe {new}", 1))
        print("release_notes/latest.md: заголовок обновлён — проверьте текст заметок.")

    for path, text in _pending.items():
        (ROOT / path).write_text(text, encoding="utf-8")
    print(f"Версия {old} -> {new}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    bump(sys.argv[1])
    subprocess.run([sys.executable, str(ROOT / "scripts" / "check_version_consistency.py")], check=True)
