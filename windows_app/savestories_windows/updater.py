from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
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
        self.last_apply_script_path: Path | None = None
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
                "User-Agent": "SaveStories-Updater",
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
            headers={"User-Agent": "SaveStories-Updater"},
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

        self._verify_digest(installer_path, release.asset.digest)

        current_executable = Path(sys.executable).resolve()
        target_dir = current_executable.parent
        current_executable_name = current_executable.name

        if not installer_path.exists():
            raise WindowsUpdaterError(
                f"Не удалось скачать установщик обновления. Лог: {update_root / 'apply_update.log'}"
            )

        script_path = update_root / "apply_update.ps1"
        log_path = update_root / "apply_update.log"
        status_path = update_root / "apply_update.status.json"
        installer_log_path = update_root / "installer.log"
        script_path.write_text(
            self._update_script_text(
                installer_path=installer_path,
                target_dir=target_dir,
                current_executable_path=current_executable,
                log_path=log_path,
                status_path=status_path,
                installer_log_path=installer_log_path,
            ),
            # PowerShell 5.1 reliably reads UTF-16 with BOM on all Windows setups.
            encoding="utf-16",
        )

        self.last_apply_script_path = script_path
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
        script_path = self.last_apply_script_path
        log_path = self.last_apply_log_path
        if script_path is None or log_path is None:
            raise WindowsUpdaterError("Сначала подготовь обновление через кнопку «Установить».")
        if not script_path.exists():
            raise WindowsUpdaterError(f"Скрипт установки не найден: {script_path}")

        try:
            subprocess.Popen(
                [
                    "powershell.exe",
                    "-NoProfile",
                    "-NonInteractive",
                    "-WindowStyle",
                    "Hidden",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(script_path),
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                cwd=str(script_path.parent),
                creationflags=(
                    subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
                    if sys.platform == "win32"
                    else 0
                ),
                close_fds=True,
            )
        except Exception as error:
            raise WindowsUpdaterError(
                f"Не удалось запустить установщик обновления: {error}. Лог: {log_path}"
            ) from error
        return str(log_path)

    def _load_config(self) -> dict:
        config_path = AppPaths.update_config_path()
        return json.loads(config_path.read_text(encoding="utf-8"))

    def _select_release_asset(self, assets: list[dict], latest_tag: str) -> ReleaseAsset:
        expected_name = f"SaveStories-Windows-Setup-{latest_tag}.exe"
        for asset in assets:
            name = str(asset.get("name") or "")
            if name != expected_name:
                continue
            return ReleaseAsset(
                name=name,
                url=str(asset.get("browser_download_url") or ""),
                size=int(asset.get("size") or 0),
                digest=str(asset.get("digest") or ""),
            )
        raise WindowsUpdaterError(f"Не удалось найти release asset {expected_name}.")

    def _version_key(self, value: str) -> tuple[int, int, int]:
        numbers: list[int] = []
        for part in value.lstrip("v").split("."):
            digits = "".join(character for character in part if character.isdigit())
            numbers.append(int(digits or "0"))
        while len(numbers) < 3:
            numbers.append(0)
        return tuple(numbers[:3])

    def _verify_digest(self, archive_path: Path, digest: str) -> None:
        if not digest.startswith("sha256:"):
            return

        expected = digest.split(":", 1)[1].strip().lower()
        actual = hashlib.sha256(archive_path.read_bytes()).hexdigest().lower()
        if actual != expected:
            raise WindowsUpdaterError("SHA256 release digest не совпал. Обновление остановлено.")

    def _update_script_text(
        self,
        *,
        installer_path: Path,
        target_dir: Path,
        current_executable_path: Path,
        log_path: Path,
        status_path: Path,
        installer_log_path: Path,
    ) -> str:
        return f"""
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$installer = "{str(installer_path)}"
$target = "{str(target_dir)}"
$currentExe = "{str(current_executable_path)}"
$logPath = "{str(log_path)}"
$statusPath = "{str(status_path)}"
$installerLogPath = "{str(installer_log_path)}"

function Write-Log([string]$message) {{
    Add-Content -Path $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $message" -Encoding UTF8
}}

function Test-FileUnlocked([string]$path) {{
    try {{
        $stream = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        return $true
    }} catch {{
        return $false
    }}
}}

try {{
    if (Test-Path $logPath) {{
        Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue
    }}
    Write-Log "Update apply started"
    Write-Log "Installer: $installer"
    Write-Log "Target: $target"
    Write-Log "Current exe: $currentExe"

    if (-not (Test-Path $installer)) {{
        throw "Installer file not found: $installer"
    }}

    for ($attempt = 1; $attempt -le 120; $attempt++) {{
        if ((-not (Test-Path $currentExe)) -or (Test-FileUnlocked $currentExe)) {{
            Write-Log "Executable is unlocked on attempt #$attempt"
            break
        }}
        Start-Sleep -Milliseconds 500
        if ($attempt -eq 120) {{
            throw "Current executable is still locked after 60 seconds: $currentExe"
        }}
    }}

    $arguments = @(
        '/SP-',
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/FORCECLOSEAPPLICATIONS',
        '/LOG="' + $installerLogPath + '"'
    )
    Write-Log "Starting installer with silent arguments."
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    Write-Log "Installer exit code: $($process.ExitCode)"
    if ($process.ExitCode -ne 0) {{
        throw "Installer exited with code $($process.ExitCode). See $installerLogPath"
    }}

    if (-not (Test-Path $currentExe)) {{
        throw "Updated executable not found after install: $currentExe"
    }}

    Write-Log "Installer finished, starting executable: $currentExe"
    '{{"status":"ok","message":"install_done"}}' | Set-Content -Path $statusPath -Encoding UTF8
    Start-Process -FilePath $currentExe
    exit 0
}} catch {{
    $msg = $_.Exception.Message
    Write-Log "ERROR: $msg"
    ('{{"status":"error","message":"' + $msg.Replace('"', "'") + '"}}') | Set-Content -Path $statusPath -Encoding UTF8
    exit 1
}}
""".strip()



