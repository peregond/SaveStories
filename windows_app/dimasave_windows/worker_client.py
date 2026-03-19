from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import asdict
from typing import Sequence

from .app_paths import AppPaths
from .models import WorkerItem, WorkerRequest, WorkerResponse


class WorkerClient:
    def __init__(self) -> None:
        self.current_process: subprocess.Popen[bytes] | None = None

    def stop_current_process(self) -> None:
        process = self.current_process
        if process is None or process.poll() is not None:
            return
        process.terminate()

    def run(self, request: WorkerRequest) -> WorkerResponse:
        AppPaths.ensure_directories()
        command, runtime = self.resolve_command()

        environment = os.environ.copy()
        environment["DIMASAVE_APP_SUPPORT"] = str(AppPaths.application_support())
        environment["DIMASAVE_BROWSER_PROFILE"] = str(AppPaths.browser_profile())
        environment["DIMASAVE_MANIFESTS"] = str(AppPaths.manifests_directory())
        environment["DIMASAVE_PLAYWRIGHT_BROWSERS"] = str(AppPaths.playwright_browsers())
        environment["DIMASAVE_DEFAULT_DOWNLOADS"] = str(AppPaths.default_downloads())
        environment["DIMASAVE_WORKER_RUNTIME"] = runtime

        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        self.current_process = process
        stdout_data, stderr_data = process.communicate((json.dumps(asdict(request)) + "\n").encode("utf-8"))
        self.current_process = None

        if process.returncode != 0 and not stdout_data:
            stderr_text = stderr_data.decode("utf-8", errors="replace").strip()
            if not stderr_text:
                stderr_text = f"Worker process failed with exit status {process.returncode}."
            return WorkerResponse.process_failure(stderr_text)

        if not stdout_data:
            stderr_text = stderr_data.decode("utf-8", errors="replace").strip() or "Worker returned no output."
            return WorkerResponse.process_failure(stderr_text)

        try:
            payload = json.loads(stdout_data.decode("utf-8"))
        except Exception:
            raw = stdout_data.decode("utf-8", errors="replace")
            return WorkerResponse.process_failure(f"Worker returned invalid JSON.\n{raw}")

        items = [WorkerItem(**item) for item in payload.get("items", [])]
        return WorkerResponse(
            ok=payload.get("ok", False),
            status=payload.get("status", "unknown"),
            message=payload.get("message", ""),
            data=payload.get("data", {}) or {},
            items=items,
            logs=payload.get("logs", []) or [],
        )

    @staticmethod
    def resolve_command() -> tuple[Sequence[str], str]:
        try:
            script = AppPaths.node_worker_script()
            return ([str(AppPaths.node_executable()), str(script)], "node")
        except FileNotFoundError:
            pass

        try:
            script = AppPaths.node_worker_script()
            node = shutil.which("node")
            if node:
                return ([node, str(script)], "node")
        except FileNotFoundError:
            pass

        if getattr(sys, "frozen", False):
            raise RuntimeError("Не удалось найти встроенный Node runtime. Переустанови приложение.")

        script = AppPaths.worker_script()
        python_command = WorkerClient.resolve_python_command()
        return (list(python_command) + [str(script)], "python")

    @staticmethod
    def resolve_python_command() -> Sequence[str]:
        if getattr(sys, "frozen", False):
            return [sys.executable, "--worker-bridge"]

        candidate = AppPaths.worker_python()
        if candidate.exists():
            return [str(candidate)]

        py_launcher = shutil.which("py")
        if py_launcher:
            return [py_launcher, "-3"]

        python = shutil.which("python")
        if python:
            return [python]

        raise RuntimeError("Python 3 не найден. Установи Python 3.13+ и затем выполни настройку движка.")
