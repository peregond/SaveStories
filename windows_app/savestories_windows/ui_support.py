from __future__ import annotations

import math
import os
import subprocess
import sys
import threading
import traceback
from datetime import datetime
from pathlib import Path
from typing import Callable

from PySide6 import QtCore, QtGui, QtWidgets

from .app_paths import AppPaths
from .common_utils import (
    batch_status_title,
    normalize_profile_link,
    parse_batch_links,
    suggested_recent_list_title,
)
from .models import WorkerRequest, WorkerResponse
from .updater import ReleaseInfo, WindowsUpdater
from .worker_client import WorkerClient


def display_now() -> str:
    return datetime.now().astimezone().strftime("%d.%m.%Y %H:%M:%S")


def crash_log_path() -> Path:
    return AppPaths.logs_directory() / "windows-crash.log"


def write_crash_log(title: str, details: str) -> None:
    try:
        AppPaths.ensure_directories()
        with crash_log_path().open("a", encoding="utf-8") as handle:
            handle.write(f"{display_now()}  {title}\n{details.rstrip()}\n\n")
    except Exception:
        pass


def install_global_exception_hooks() -> None:
    def handle_exception(exc_type, exc_value, exc_traceback) -> None:
        details = "".join(traceback.format_exception(exc_type, exc_value, exc_traceback))
        write_crash_log("Unhandled exception", details)
        sys.__excepthook__(exc_type, exc_value, exc_traceback)

    def handle_thread_exception(args: threading.ExceptHookArgs) -> None:
        details = "".join(
            traceback.format_exception(args.exc_type, args.exc_value, args.exc_traceback)
        )
        write_crash_log("Unhandled thread exception", details)

    sys.excepthook = handle_exception
    threading.excepthook = handle_thread_exception


def app_version() -> str:
    version_path = AppPaths.resource_root() / "VERSION"
    if version_path.exists():
        value = version_path.read_text(encoding="utf-8").strip()
        if value:
            return value
    return "0.4.29"


class WorkerTask(QtCore.QThread):
    response_ready = QtCore.Signal(object)

    def __init__(self, client: WorkerClient, request: WorkerRequest) -> None:
        super().__init__()
        self.client = client
        self.request = request

    def run(self) -> None:
        try:
            response = self.client.run(self.request)
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("WorkerTask failure", details)
            response = WorkerResponse.process_failure(f"WorkerTask failure:\n{error}")
        self.response_ready.emit(response)


class BootstrapTask(QtCore.QThread):
    finished_output = QtCore.Signal(bool, str)

    def run(self) -> None:
        try:
            script = AppPaths.bootstrap_script()
            command = [
                "powershell.exe",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
            ]
            env = os.environ.copy()
            env["SAVESTORIES_APP_SUPPORT"] = str(AppPaths.application_support())
            creationflags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
            process = subprocess.run(
                command,
                capture_output=True,
                text=True,
                env=env,
                creationflags=creationflags,
            )
            output = (process.stdout or process.stderr or "").strip()
            self.finished_output.emit(process.returncode == 0, output)
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("BootstrapTask failure", details)
            self.finished_output.emit(False, f"BootstrapTask failure:\n{error}")


class UpdateCheckTask(QtCore.QThread):
    finished_output = QtCore.Signal(bool, str, object)

    def __init__(self, updater: WindowsUpdater, current_version: str) -> None:
        super().__init__()
        self.updater = updater
        self.current_version = current_version

    def run(self) -> None:
        try:
            status, release = self.updater.check_latest_release(self.current_version)
            self.finished_output.emit(True, status, release)
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("UpdateCheckTask failure", details)
            self.finished_output.emit(False, str(error), None)


class UpdateInstallTask(QtCore.QThread):
    finished_output = QtCore.Signal(bool, str)
    progress_output = QtCore.Signal(int, str)

    def __init__(self, updater: WindowsUpdater, release: ReleaseInfo) -> None:
        super().__init__()
        self.updater = updater
        self.release = release

    def run(self) -> None:
        try:
            message = self.updater.prepare_install(self.release, progress_callback=self.emit_progress)
            self.finished_output.emit(True, message)
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("UpdateInstallTask failure", details)
            self.finished_output.emit(False, str(error))

    def emit_progress(self, percent: int, message: str) -> None:
        self.progress_output.emit(percent, message)


class ConfettiOverlay(QtWidgets.QWidget):
    def __init__(self, parent: QtWidgets.QWidget) -> None:
        super().__init__(parent)
        self.setAttribute(QtCore.Qt.WA_TransparentForMouseEvents, True)
        self.setAttribute(QtCore.Qt.WA_TranslucentBackground, True)
        self.hide()
        self._timer = QtCore.QTimer(self)
        self._timer.setInterval(16)
        self._timer.timeout.connect(self._tick)
        self._particles: list[dict[str, float | QtGui.QColor]] = []
        self._remaining_frames = 0

    def launch(self) -> None:
        parent = self.parentWidget()
        if parent is None:
            return
        self.setGeometry(parent.rect())
        self._particles = self._spawn_particles()
        self._remaining_frames = 150
        self.show()
        self.raise_()
        self._timer.start()
        self.update()

    def _spawn_particles(self) -> list[dict[str, float | QtGui.QColor]]:
        colors = [
            QtGui.QColor("#b9ff00"),
            QtGui.QColor("#d7ff57"),
            QtGui.QColor("#8cf59f"),
            QtGui.QColor("#7fd3ff"),
            QtGui.QColor("#ffffff"),
        ]
        origin_x = self.width() / 2
        origin_y = self.height() * 0.2
        particles: list[dict[str, float | QtGui.QColor]] = []
        for index in range(90):
            angle = -1.15 + (2.3 * index / 89.0)
            speed = 7.0 + (index % 7) * 0.55
            particles.append(
                {
                    "x": origin_x,
                    "y": origin_y,
                    "vx": speed * math.cos(angle),
                    "vy": -abs(speed * math.sin(angle)) - 2.0,
                    "size": 6.0 + (index % 5) * 1.8,
                    "rotation": float((index * 19) % 360),
                    "rotation_speed": -8.0 + (index % 9) * 1.9,
                    "life": 1.0,
                    "color": colors[index % len(colors)],
                }
            )
        return particles

    def _tick(self) -> None:
        gravity = 0.24
        drag = 0.995
        for particle in self._particles:
            particle["x"] = float(particle["x"]) + float(particle["vx"])
            particle["y"] = float(particle["y"]) + float(particle["vy"])
            particle["vx"] = float(particle["vx"]) * drag
            particle["vy"] = float(particle["vy"]) + gravity
            particle["rotation"] = float(particle["rotation"]) + float(particle["rotation_speed"])
            particle["life"] = max(0.0, float(particle["life"]) - 0.0065)
        self._remaining_frames -= 1
        self.update()
        if self._remaining_frames <= 0 or not any(float(p["life"]) > 0.0 for p in self._particles):
            self._timer.stop()
            self.hide()

    def paintEvent(self, event: QtGui.QPaintEvent) -> None:
        del event
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.Antialiasing, True)
        for particle in self._particles:
            life = float(particle["life"])
            if life <= 0.0:
                continue
            painter.save()
            painter.setOpacity(min(1.0, life * 1.15))
            painter.translate(float(particle["x"]), float(particle["y"]))
            painter.rotate(float(particle["rotation"]))
            color = QtGui.QColor(particle["color"])
            painter.setPen(QtCore.Qt.NoPen)
            painter.setBrush(color)
            size = float(particle["size"])
            rect = QtCore.QRectF(-size / 2, -size / 3, size, size * 0.66)
            painter.drawRoundedRect(rect, 2.2, 2.2)
            painter.restore()


class SettingsDialog(QtWidgets.QDialog):
    refresh_requested = QtCore.Signal()
    bootstrap_requested = QtCore.Signal()
    login_requested = QtCore.Signal()
    session_check_requested = QtCore.Signal()
    open_runtime_requested = QtCore.Signal()
    update_check_requested = QtCore.Signal()

    def __init__(self, parent: QtWidgets.QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Настройки")
        self.setModal(True)
        self.resize(560, 420)

        layout = QtWidgets.QVBoxLayout(self)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(14)

        title = QtWidgets.QLabel("Служебные настройки")
        title.setObjectName("dialogTitle")
        layout.addWidget(title)

        self.worker_label = QtWidgets.QLabel("Воркер ещё не проверялся.")
        self.worker_label.setWordWrap(True)
        self.session_label = QtWidgets.QLabel("Состояние сессии неизвестно.")
        self.session_label.setWordWrap(True)
        self.update_label = QtWidgets.QLabel("Автообновление ещё не инициализировано.")
        self.update_label.setWordWrap(True)
        self.runtime_text = QtWidgets.QPlainTextEdit()
        self.runtime_text.setReadOnly(True)
        self.runtime_text.setMinimumHeight(170)

        layout.addWidget(self._group("Обновления", self.update_label))
        layout.addWidget(self._group("Воркер", self.worker_label))
        layout.addWidget(self._group("Сессия", self.session_label))
        layout.addWidget(self._group("Среда", self.runtime_text), 1)

        button_row = QtWidgets.QHBoxLayout()
        button_row.setSpacing(10)
        for text, signal in [
            ("Установить движок", self.bootstrap_requested),
            ("Проверить среду", self.refresh_requested),
            ("Открыть браузер для входа", self.login_requested),
            ("Проверить сессию", self.session_check_requested),
            ("Проверить обновления", self.update_check_requested),
            ("Открыть папку среды", self.open_runtime_requested),
        ]:
            button = QtWidgets.QPushButton(text)
            button.clicked.connect(signal)
            button_row.addWidget(button)
        layout.addLayout(button_row)

    def _group(self, title: str, content: QtWidgets.QWidget) -> QtWidgets.QWidget:
        box = QtWidgets.QGroupBox(title)
        box_layout = QtWidgets.QVBoxLayout(box)
        box_layout.setContentsMargins(12, 12, 12, 12)
        box_layout.addWidget(content)
        return box

    def update_state(
        self,
        *,
        worker_summary: str,
        session_summary: str,
        runtime_summary: str,
        update_summary: str,
    ) -> None:
        self.update_label.setText(update_summary)
        self.worker_label.setText(worker_summary)
        self.session_label.setText(session_summary)
        self.runtime_text.setPlainText(runtime_summary)
