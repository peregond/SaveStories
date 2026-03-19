from __future__ import annotations

import os
import sys
from pathlib import Path


class AppPaths:
    app_name = "DimaSave"

    @staticmethod
    def project_root() -> Path:
        return Path(__file__).resolve().parents[2]

    @staticmethod
    def resource_root() -> Path:
        if getattr(sys, "frozen", False):
            return Path(getattr(sys, "_MEIPASS", Path(sys.executable).resolve().parent))
        return AppPaths.project_root()

    @staticmethod
    def application_support() -> Path:
        override = os.environ.get("DIMASAVE_APP_SUPPORT")
        if override:
            return Path(override).expanduser()

        root = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA")
        if root:
            return Path(root) / AppPaths.app_name
        return Path.home() / "AppData" / "Local" / AppPaths.app_name

    @staticmethod
    def worker_root() -> Path:
        return AppPaths.application_support() / "worker"

    @staticmethod
    def worker_python() -> Path:
        return AppPaths.worker_root() / ".venv" / "Scripts" / "python.exe"

    @staticmethod
    def node_executable() -> Path:
        candidates = [
            AppPaths.resource_root() / "runtime" / "node" / "node.exe",
            AppPaths.resource_root() / "runtime" / "node" / "bin" / "node.exe",
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        raise FileNotFoundError("Не удалось найти встроенный runtime/node/node.exe")

    @staticmethod
    def node_worker_script() -> Path:
        candidates = [
            AppPaths.resource_root() / "node_worker" / "bridge.mjs",
            AppPaths.project_root() / "node_worker" / "bridge.mjs",
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        raise FileNotFoundError("Не удалось найти node_worker/bridge.mjs")

    @staticmethod
    def browser_profile() -> Path:
        return AppPaths.worker_root() / "browser-profile"

    @staticmethod
    def manifests_directory() -> Path:
        return AppPaths.application_support() / "manifests"

    @staticmethod
    def logs_directory() -> Path:
        return AppPaths.application_support() / "logs"

    @staticmethod
    def playwright_browsers() -> Path:
        bundled = AppPaths.resource_root() / "runtime" / "ms-playwright"
        if bundled.exists():
            return bundled
        return AppPaths.worker_root() / "ms-playwright"

    @staticmethod
    def has_embedded_runtime() -> bool:
        try:
            AppPaths.node_executable()
            AppPaths.node_worker_script()
            return AppPaths.playwright_browsers().exists()
        except FileNotFoundError:
            return False

    @staticmethod
    def default_downloads() -> Path:
        user_profile = os.environ.get("USERPROFILE")
        if user_profile:
            return Path(user_profile) / "Downloads" / AppPaths.app_name
        return AppPaths.application_support() / "Downloads"

    @staticmethod
    def worker_script() -> Path:
        candidates = [
            AppPaths.resource_root() / "worker" / "bridge.py",
            AppPaths.project_root() / "Sources" / "DimaSave" / "Resources" / "worker" / "bridge.py",
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        raise FileNotFoundError("Не удалось найти worker/bridge.py")

    @staticmethod
    def bootstrap_script() -> Path:
        candidates = [
            AppPaths.resource_root() / "windows_app" / "bootstrap_node_worker.ps1",
            AppPaths.project_root() / "windows_app" / "bootstrap_node_worker.ps1",
            AppPaths.resource_root() / "windows_app" / "bootstrap_worker.ps1",
            AppPaths.project_root() / "windows_app" / "bootstrap_worker.ps1",
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        raise FileNotFoundError("Не удалось найти bootstrap_worker.ps1")

    @staticmethod
    def ensure_directories() -> None:
        for path in [
            AppPaths.application_support(),
            AppPaths.worker_root(),
            AppPaths.browser_profile(),
            AppPaths.manifests_directory(),
            AppPaths.logs_directory(),
            AppPaths.playwright_browsers(),
            AppPaths.default_downloads(),
        ]:
            path.mkdir(parents=True, exist_ok=True)
