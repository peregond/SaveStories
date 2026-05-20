from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import asdict
from typing import Sequence

from .app_paths import AppPaths
from .models import WorkerBatchResult, WorkerCounts, WorkerItem, WorkerRequest, WorkerResponse, WorkerRuntime


class WorkerClient:
    def __init__(self) -> None:
        self.current_process: subprocess.Popen[bytes] | None = None
        self.login_process: subprocess.Popen[bytes] | None = None

    def stop_current_process(self) -> None:
        process = self.current_process
        if process is None or process.poll() is not None:
            return
        process.terminate()

    def start_detached_login(self, request: WorkerRequest) -> None:
        AppPaths.ensure_directories()
        command, runtime = self.resolve_command(request)

        environment = os.environ.copy()
        environment["SAVESTORIES_APP_SUPPORT"] = str(AppPaths.application_support())
        environment["SAVESTORIES_BROWSER_PROFILE"] = str(AppPaths.browser_profile())
        environment["SAVESTORIES_MANIFESTS"] = str(AppPaths.manifests_directory())
        environment["SAVESTORIES_PLAYWRIGHT_BROWSERS"] = str(AppPaths.playwright_browsers())
        environment["SAVESTORIES_DEFAULT_DOWNLOADS"] = str(AppPaths.default_downloads())
        environment["SAVESTORIES_LOGS"] = str(AppPaths.logs_directory())
        environment["SAVESTORIES_WORKER_RUNTIME"] = runtime

        popen_options = self._windows_popen_options(detached=True)

        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=environment,
            close_fds=True,
            **popen_options,
        )
        self.login_process = process
        assert process.stdin is not None
        process.stdin.write((json.dumps(asdict(request)) + "\n").encode("utf-8"))
        process.stdin.flush()
        process.stdin.close()

    def run(self, request: WorkerRequest) -> WorkerResponse:
        AppPaths.ensure_directories()
        command, runtime = self.resolve_command(request)

        environment = os.environ.copy()
        environment["SAVESTORIES_APP_SUPPORT"] = str(AppPaths.application_support())
        environment["SAVESTORIES_BROWSER_PROFILE"] = str(AppPaths.browser_profile())
        environment["SAVESTORIES_MANIFESTS"] = str(AppPaths.manifests_directory())
        environment["SAVESTORIES_PLAYWRIGHT_BROWSERS"] = str(AppPaths.playwright_browsers())
        environment["SAVESTORIES_DEFAULT_DOWNLOADS"] = str(AppPaths.default_downloads())
        environment["SAVESTORIES_LOGS"] = str(AppPaths.logs_directory())
        environment["SAVESTORIES_WORKER_RUNTIME"] = runtime

        popen_options = self._windows_popen_options(detached=False)

        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            close_fds=True,
            **popen_options,
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

        stdout_text = stdout_data.decode("utf-8", errors="replace")
        try:
            payload, stdout_tail = self._load_first_json_object(stdout_text)
        except Exception:
            return WorkerResponse.process_failure(f"Worker returned invalid JSON.\n{stdout_text}")

        items = [WorkerItem(**item) for item in payload.get("items", [])]
        counts_payload = payload.get("counts")
        counts = WorkerCounts(**counts_payload) if isinstance(counts_payload, dict) else None
        batch_results = [
            WorkerBatchResult(**item)
            for item in payload.get("batchResults", [])
            if isinstance(item, dict)
        ]
        runtime_payload = payload.get("runtime")
        runtime = WorkerRuntime(**runtime_payload) if isinstance(runtime_payload, dict) else None
        return WorkerResponse(
            ok=payload.get("ok", False),
            status=payload.get("status", "unknown"),
            message=payload.get("message", ""),
            protocolVersion=payload.get("protocolVersion"),
            data=payload.get("data", {}) or {},
            counts=counts,
            batchResults=batch_results,
            runtime=runtime,
            diagnostics=payload.get("diagnostics", {}) or {},
            items=items,
            logs=(payload.get("logs", []) or []) + ([f"worker_stdout_tail={stdout_tail}"] if stdout_tail else []),
        )

    @staticmethod
    def _load_first_json_object(stdout_text: str) -> tuple[dict, str]:
        decoder = json.JSONDecoder()
        start = stdout_text.find("{")
        if start < 0:
            raise ValueError("Worker stdout does not contain a JSON object.")
        payload, end = decoder.raw_decode(stdout_text[start:])
        if not isinstance(payload, dict):
            raise ValueError("Worker JSON response must be an object.")
        return payload, stdout_text[start + end :].strip()

    @staticmethod
    def resolve_command(request: WorkerRequest | None = None) -> tuple[Sequence[str], str]:
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

        raise RuntimeError("Node runtime не найден. Подготовь движок в настройках приложения.")

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

    @staticmethod
    def _windows_popen_options(*, detached: bool) -> dict:
        if os.name != "nt":
            return {}

        creationflags = subprocess.CREATE_NO_WINDOW
        if detached:
            creationflags |= subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP

        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startupinfo.wShowWindow = 0
        return {
            "creationflags": creationflags,
            "startupinfo": startupinfo,
        }
