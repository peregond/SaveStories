from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import ctypes
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .app_paths import AppPaths


class WindowsUpdaterError(RuntimeError):
    pass


@dataclass
class ReleaseAsset:
    name: str
    url: str
    size: int
    digest: str
    checksum_url: str = ""


@dataclass
class ReleaseInfo:
    version: str
    tag: str
    title: str
    notes: str
    html_url: str
    published_at: str
    asset: ReleaseAsset


class WindowsUpdater:
    def __init__(self) -> None:
        self.config = self._load_config()
        self.last_installer_path: Path | None = None
        self.last_apply_log_path: Path | None = None

    @property
    def is_available(self) -> bool:
        return bool(self.config.get("windowsLatestReleaseAPI"))

    @property
    def supports_auto_install(self) -> bool:
        if not getattr(sys, "frozen", False):
            return False
        executable = Path(sys.executable).resolve()
        return executable.parent.joinpath("unins000.exe").exists()

    @property
    def summary(self) -> str:
        api_url = str(self.config.get("windowsLatestReleaseAPI", "")).strip()
        if not api_url:
            return "Проверка обновлений отключена: не найден адрес latest release API."
        if not self.supports_auto_install:
            return (
                "Обновления проверяются, но автоустановка отключена: "
                "эта Windows-сборка запущена не из установленной версии."
            )
        return f"Проверяю релизы через GitHub API: {api_url}"

    def check_latest_release(self, current_version: str) -> tuple[str, ReleaseInfo | None]:
        api_url = str(self.config.get("windowsLatestReleaseAPI", "")).strip()
        if not api_url:
            return ("disabled", None)

        request = urllib.request.Request(
            api_url,
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": "SaveMe-Updater",
            },
        )

        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.loads(response.read().decode("utf-8"))

        latest_tag = str(payload.get("tag_name", "")).strip()
        latest_version = latest_tag.lstrip("v")
        if not latest_version:
            raise WindowsUpdaterError("GitHub API не вернул tag_name для latest release.")

        if self._version_key(latest_version) <= self._version_key(current_version):
            return ("up_to_date", None)

        asset = self._select_release_asset(payload.get("assets", []), latest_tag)
        release = ReleaseInfo(
            version=latest_version,
            tag=latest_tag,
            title=str(payload.get("name") or latest_tag),
            notes=str(payload.get("body") or "").strip(),
            html_url=str(payload.get("html_url") or ""),
            published_at=str(payload.get("published_at") or ""),
            asset=asset,
        )
        return ("update_available", release)

    def prepare_install(
        self,
        release: ReleaseInfo,
        progress_callback: Callable[[int, str], None] | None = None,
    ) -> str:
        if not self.supports_auto_install:
            raise WindowsUpdaterError(
                "Автоустановка доступна только для версии, установленной через инсталлятор. "
                "Для portable-сборки скачай новый установщик вручную."
            )

        AppPaths.ensure_directories()
        update_root = AppPaths.updates_directory() / release.version
        if update_root.exists():
            shutil.rmtree(update_root)
        update_root.mkdir(parents=True, exist_ok=True)

        installer_path = update_root / release.asset.name
        request = urllib.request.Request(
            release.asset.url,
            headers={"User-Agent": "SaveMe-Updater"},
        )
        self._emit_progress(progress_callback, 0, f"Скачивание обновления {release.version}: 0%")
        with urllib.request.urlopen(request, timeout=60) as response, installer_path.open("wb") as handle:
            content_length = response.headers.get("Content-Length")
            total_bytes = int(content_length) if content_length and content_length.isdigit() else 0
            if total_bytes <= 0:
                total_bytes = int(release.asset.size or 0)

            downloaded_bytes = 0
            last_percent = -1
            while True:
                chunk = response.read(1024 * 256)
                if not chunk:
                    break
                handle.write(chunk)
                downloaded_bytes += len(chunk)
                if total_bytes > 0:
                    percent = int((downloaded_bytes * 100) / total_bytes)
                    percent = max(0, min(100, percent))
                    if percent != last_percent:
                        last_percent = percent
                        self._emit_progress(
                            progress_callback,
                            percent,
                            f"Скачивание обновления {release.version}: {percent}%",
                        )

        self._emit_progress(progress_callback, 100, f"Скачивание обновления {release.version}: 100%")

        checksum_text = self._download_checksum(release.asset.checksum_url)
        self._verify_digest(installer_path, release.asset.digest, checksum_text)
        self._verify_installer_signature(installer_path)

        if not installer_path.exists():
            raise WindowsUpdaterError(
                f"Не удалось скачать установщик обновления. Лог: {update_root / 'apply_update.log'}"
            )

        log_path = update_root / "apply_update.log"
        installer_log_path = update_root / "installer.log"
        log_path.write_text(
            f"Prepared installer: {installer_path}\nInstaller log: {installer_log_path}\n",
            encoding="utf-8",
        )

        self.last_installer_path = installer_path
        self.last_apply_log_path = log_path

        return (
            f"Обновление {release.version} подготовлено. "
            "Нажми кнопку «Установить обновление» в левом меню, чтобы применить его."
        )

    def _emit_progress(
        self,
        callback: Callable[[int, str], None] | None,
        percent: int,
        message: str,
    ) -> None:
        if callback is None:
            return
        callback(percent, message)

    def launch_prepared_install(self) -> str:
        installer_path = self.last_installer_path
        log_path = self.last_apply_log_path
        if installer_path is None or log_path is None:
            raise WindowsUpdaterError("Сначала подготовь обновление через кнопку «Установить».")
        if not installer_path.exists():
            raise WindowsUpdaterError(f"Установщик обновления не найден: {installer_path}")

        installer_log_path = installer_path.parent / "installer.log"
        arguments = " ".join(
            [
                "/SP-",
                "/CLOSEAPPLICATIONS",
                "/FORCECLOSEAPPLICATIONS",
                "/NORESTART",
                f'/LOG="{installer_log_path}"',
            ]
        )
        try:
            result = ctypes.windll.shell32.ShellExecuteW(
                None,
                "runas",
                str(installer_path),
                arguments,
                str(installer_path.parent),
                1,
            )
        except Exception as error:
            raise WindowsUpdaterError(
                f"Не удалось запустить установщик обновления: {error}. Лог: {log_path}"
            ) from error
        if result <= 32:
            raise WindowsUpdaterError(
                f"ShellExecuteW не смог запустить установщик (код {result}). Лог: {log_path}"
            )

        with log_path.open("a", encoding="utf-8") as handle:
            handle.write(
                f"Launched installer: {installer_path}\n"
                f"Installer args: {arguments}\n"
                f"Installer log: {installer_log_path}\n"
            )
        return str(log_path)

    def _load_config(self) -> dict:
        config_path = AppPaths.update_config_path()
        return json.loads(config_path.read_text(encoding="utf-8"))

    def _select_release_asset(self, assets: list[dict], latest_tag: str) -> ReleaseAsset:
        normalized_tag = latest_tag.strip()
        normalized_version = normalized_tag.lstrip("vV")
        expected_names = [
            f"SaveMe-Windows-Setup-{normalized_tag}.exe",
            f"SaveMe-Windows-Setup-v{normalized_version}.exe",
            f"SaveMe-Windows-Setup-{normalized_version}.exe",
            f"SaveStories-Windows-Setup-{normalized_tag}.exe",
            f"SaveStories-Windows-Setup-v{normalized_version}.exe",
            f"SaveStories-Windows-Setup-{normalized_version}.exe",
        ]
        fallback_asset: dict | None = None
        checksum_by_name = {
            str(asset.get("name") or ""): str(asset.get("browser_download_url") or "")
            for asset in assets
            if str(asset.get("name") or "").endswith(".sha256")
        }

        def checksum_url_for(name: str) -> str:
            return checksum_by_name.get(f"{name}.sha256", "")

        for asset in assets:
            name = str(asset.get("name") or "")
            if name in expected_names:
                return ReleaseAsset(
                    name=name,
                    url=str(asset.get("browser_download_url") or ""),
                    size=int(asset.get("size") or 0),
                    digest=str(asset.get("digest") or ""),
                    checksum_url=checksum_url_for(name),
                )
            if (
                fallback_asset is None
                and (
                    name.startswith("SaveMe-Windows-Setup-")
                    or name.startswith("SaveStories-Windows-Setup-")
                )
                and name.endswith(".exe")
            ):
                fallback_asset = asset

        if fallback_asset is not None:
            return ReleaseAsset(
                name=str(fallback_asset.get("name") or ""),
                url=str(fallback_asset.get("browser_download_url") or ""),
                size=int(fallback_asset.get("size") or 0),
                digest=str(fallback_asset.get("digest") or ""),
                checksum_url=checksum_url_for(str(fallback_asset.get("name") or "")),
            )

        available = ", ".join(str(item.get("name") or "") for item in assets) or "пусто"
        raise WindowsUpdaterError(
            "Не удалось найти установщик Windows в assets релиза. "
            f"Ожидались варианты: {', '.join(expected_names)}. "
            f"Доступно: {available}."
        )

    def _version_key(self, value: str) -> tuple[int, int, int]:
        numbers: list[int] = []
        for part in value.lstrip("v").split("."):
            digits = "".join(character for character in part if character.isdigit())
            numbers.append(int(digits or "0"))
        while len(numbers) < 3:
            numbers.append(0)
        return tuple(numbers[:3])

    def _download_checksum(self, checksum_url: str) -> str:
        if not checksum_url:
            return ""
        request = urllib.request.Request(
            checksum_url,
            headers={"User-Agent": "SaveMe-Updater"},
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.read().decode("utf-8", errors="replace")

    def _verify_digest(self, archive_path: Path, digest: str, checksum_text: str = "") -> None:
        expected = ""
        if digest.startswith("sha256:"):
            expected = digest.split(":", 1)[1].strip().lower()
        elif checksum_text:
            expected = checksum_text.strip().split()[0].lower()

        if not expected:
            raise WindowsUpdaterError("У релиза нет SHA256 digest для установщика. Автоустановка остановлена.")

        if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
            raise WindowsUpdaterError("SHA256 digest релиза имеет некорректный формат. Обновление остановлено.")

        actual = hashlib.sha256(archive_path.read_bytes()).hexdigest().lower()
        if actual != expected:
            raise WindowsUpdaterError("SHA256 release digest не совпал. Обновление остановлено.")

    def _verify_installer_signature(self, installer_path: Path) -> None:
        if os.name != "nt":
            return

        command = [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            (
                "$signature = Get-AuthenticodeSignature -LiteralPath $args[0]; "
                "if ($signature.Status -ne 'Valid') { "
                "Write-Error ('Installer signature is not valid: ' + $signature.Status); exit 1 "
                "}"
            ),
            str(installer_path),
        ]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            details = (result.stderr or result.stdout or "unknown signature verification error").strip()
            raise WindowsUpdaterError(f"Подпись установщика обновления недействительна. {details}")




