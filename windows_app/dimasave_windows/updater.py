from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

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
    def summary(self) -> str:
        api_url = str(self.config.get("windowsLatestReleaseAPI", "")).strip()
        if not api_url:
            return "Проверка обновлений отключена: не найден адрес latest release API."
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

    def prepare_install(self, release: ReleaseInfo) -> str:
        AppPaths.ensure_directories()
        update_root = AppPaths.updates_directory() / release.version
        if update_root.exists():
            shutil.rmtree(update_root)
        update_root.mkdir(parents=True, exist_ok=True)

        archive_path = update_root / release.asset.name
        request = urllib.request.Request(
            release.asset.url,
            headers={"User-Agent": "SaveStories-Updater"},
        )
        with urllib.request.urlopen(request, timeout=60) as response, archive_path.open("wb") as handle:
            shutil.copyfileobj(response, handle)

        self._verify_digest(archive_path, release.asset.digest)

        extracted_root = update_root / "extracted"
        extracted_root.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive_path) as archive:
            archive.extractall(extracted_root)

        source_dir = self._resolve_extracted_root(extracted_root)
        target_dir = Path(__file__).resolve()
        if getattr(sys, "frozen", False):
            target_dir = Path(sys.executable).resolve()
        target_dir = target_dir.parent
        executable_name = target_dir.joinpath("SaveStories-Windows.exe").name
        source_dir = self._resolve_payload_root(source_dir, executable_name)
        if not source_dir.joinpath(executable_name).exists():
            raise WindowsUpdaterError(
                f"В архиве обновления не найден {executable_name}. Лог: {update_root / 'apply_update.log'}"
            )

        script_path = update_root / "apply_update.ps1"
        log_path = update_root / "apply_update.log"
        status_path = update_root / "apply_update.status.json"
        script_path.write_text(
            self._update_script_text(
                source_dir=source_dir,
                target_dir=target_dir,
                executable_name=executable_name,
                log_path=log_path,
                status_path=status_path,
            ),
            encoding="utf-8",
        )

        self.last_apply_script_path = script_path
        self.last_apply_log_path = log_path

        return (
            f"Обновление {release.version} подготовлено. "
            "Нажми «Перезапустить и установить», чтобы применить его сразу."
        )

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
        expected_name = f"SaveStories-Windows-{latest_tag}.zip"
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

    def _resolve_extracted_root(self, extracted_root: Path) -> Path:
        directories = [entry for entry in extracted_root.iterdir() if entry.is_dir()]
        if len(directories) == 1:
            return directories[0]
        return extracted_root

    def _resolve_payload_root(self, root: Path, executable_name: str) -> Path:
        if root.joinpath(executable_name).exists():
            return root
        for candidate in root.rglob(executable_name):
            if candidate.is_file():
                return candidate.parent
        return root

    def _update_script_text(
        self,
        *,
        source_dir: Path,
        target_dir: Path,
        executable_name: str,
        log_path: Path,
        status_path: Path,
    ) -> str:
        return f"""
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$source = "{str(source_dir)}"
$target = "{str(target_dir)}"
$exe = Join-Path $target "{executable_name}"
$logPath = "{str(log_path)}"
$statusPath = "{str(status_path)}"

function Write-Log([string]$message) {{
    Add-Content -Path $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $message" -Encoding UTF8
}}

try {{
    if (Test-Path $logPath) {{
        Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue
    }}
    Write-Log "Update apply started"
    Write-Log "Source: $source"
    Write-Log "Target: $target"

    if (-not (Test-Path $source)) {{
        throw "Папка распаковки не найдена: $source"
    }}
    if (-not (Test-Path (Join-Path $source "{executable_name}"))) {{
        throw "В распакованном обновлении нет {executable_name}: $source"
    }}

    for ($attempt = 1; $attempt -le 120; $attempt++) {{
        Start-Sleep -Milliseconds 500
        robocopy $source $target /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        $code = $LASTEXITCODE
        Write-Log "Attempt #$attempt robocopy exit code: $code"
        if ($code -le 7) {{
            Write-Log "Copy finished, starting executable: $exe"
            '{{"status":"ok","message":"copy_done"}}' | Set-Content -Path $statusPath -Encoding UTF8
            Start-Process -FilePath $exe
            exit 0
        }}
    }}
    throw "Не удалось заменить файлы после 120 попыток (60 секунд)."
}} catch {{
    $msg = $_.Exception.Message
    Write-Log "ERROR: $msg"
    ('{{"status":"error","message":"' + $msg.Replace('"', "'") + '"}}') | Set-Content -Path $statusPath -Encoding UTF8
    exit 1
}}
""".strip()


