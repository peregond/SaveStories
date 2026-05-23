from __future__ import annotations

import ctypes
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


def ui_scale_factor() -> float:
    app = QtWidgets.QApplication.instance()
    screen = app.primaryScreen() if app is not None else QtGui.QGuiApplication.primaryScreen()
    if screen is None:
        return 1.0
    try:
        factor = float(screen.logicalDotsPerInch()) / 96.0
    except Exception:
        factor = 1.0
    return max(1.0, factor)


def scaled(px: int) -> int:
    return max(1, int(round(px / ui_scale_factor())))


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
    return "0.6.62"


def prevent_system_sleep() -> bool:
    if os.name != "nt":
        return False
    try:
        result = ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | 0x00000001)
    except Exception:
        return False
    return bool(result)


def restore_system_sleep() -> bool:
    if os.name != "nt":
        return False
    try:
        result = ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
    except Exception:
        return False
    return bool(result)


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


class SettingsDialog(QtWidgets.QWidget):
    refresh_requested = QtCore.Signal()
    bootstrap_requested = QtCore.Signal()
    login_requested = QtCore.Signal()
    session_check_requested = QtCore.Signal()
    open_runtime_requested = QtCore.Signal()
    update_check_requested = QtCore.Signal()
    apply_update_requested = QtCore.Signal()
    prevent_sleep_toggled = QtCore.Signal(bool)
    theme_changed = QtCore.Signal(str)

    def __init__(self, parent: QtWidgets.QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("settingsPage")

        layout = QtWidgets.QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(scaled(12))

        title = QtWidgets.QLabel("Параметры приложения")
        title.setObjectName("dialogTitle")
        layout.addWidget(title)

        subtitle = QtWidgets.QLabel("Обновления, поведение во время выгрузки и подключение к Instagram собраны в одном месте.")
        subtitle.setWordWrap(True)
        subtitle.setObjectName("dialogSubtitle")
        layout.addWidget(subtitle)

        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QtWidgets.QFrame.NoFrame)
        layout.addWidget(scroll, 1)

        scroll_host = QtWidgets.QWidget()
        scroll.setWidget(scroll_host)
        content = QtWidgets.QVBoxLayout(scroll_host)
        content.setContentsMargins(0, 0, 0, 0)
        content.setSpacing(scaled(12))

        overview = QtWidgets.QFrame()
        overview.setObjectName("settingsHero")
        overview_layout = QtWidgets.QHBoxLayout(overview)
        overview_layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        overview_layout.setSpacing(scaled(12))
        overview_copy = QtWidgets.QVBoxLayout()
        overview_copy.setContentsMargins(0, 0, 0, 0)
        overview_copy.setSpacing(scaled(4))
        overview_title = QtWidgets.QLabel("Настройки Windows-клиента")
        overview_title.setObjectName("heroMiniTitle")
        overview_text = QtWidgets.QLabel("Здесь собраны обновления, среда, сессия Instagram и параметры поведения во время выгрузки.")
        overview_text.setWordWrap(True)
        overview_text.setObjectName("dialogSubtitle")
        overview_copy.addWidget(overview_title)
        overview_copy.addWidget(overview_text)
        self.settings_version_badge = QtWidgets.QLabel(app_version())
        self.settings_version_badge.setObjectName("valuePill")
        overview_layout.addLayout(overview_copy, 1)
        overview_layout.addWidget(self.settings_version_badge, 0, QtCore.Qt.AlignTop | QtCore.Qt.AlignRight)
        content.addWidget(overview)

        self.worker_label = QtWidgets.QLabel("Воркер ещё не проверялся.")
        self.worker_label.setWordWrap(True)
        self.session_label = QtWidgets.QLabel("Состояние сессии неизвестно.")
        self.session_label.setWordWrap(True)
        self.update_label = QtWidgets.QLabel("Автообновление ещё не инициализировано.")
        self.update_label.setWordWrap(True)
        self.runtime_text = QtWidgets.QPlainTextEdit()
        self.runtime_text.setReadOnly(True)
        self.runtime_text.setMinimumHeight(scaled(140))
        self.runtime_text.setMaximumBlockCount(300)
        self.prevent_sleep_checkbox = QtWidgets.QCheckBox("Не давать ноутбуку засыпать во время выгрузки")
        self.prevent_sleep_checkbox.setChecked(True)
        self.prevent_sleep_checkbox.toggled.connect(self.prevent_sleep_toggled)
        self.prevent_sleep_hint = QtWidgets.QLabel(
            "Во время скачивания stories или Reels приложение будет удерживать Windows в активном состоянии. "
            "Проверки среды, вход и обновления эту настройку не используют."
        )
        self.prevent_sleep_hint.setWordWrap(True)

        content.addWidget(self._settings_card("Оформление", self._theme_row()))
        content.addWidget(self._settings_card("Версия", self._version_row()))
        content.addWidget(self._settings_card("Не давать компьютеру засыпать", self._sleep_row()))
        content.addWidget(self._settings_card("Обновления", self._update_row()))
        content.addWidget(
            self._expander_card(
                "Состояние служб",
                [self._info_row("Воркер", self.worker_label), self._info_row("Сессия", self.session_label)],
                expanded=False,
            )
        )
        content.addWidget(
            self._expander_card(
                "Подключение к Instagram",
                [self._instagram_grid()],
                expanded=True,
            )
        )
        content.addWidget(
            self._expander_card(
                "Техническая информация",
                [self._info_row("Среда", self.runtime_text), self._runtime_actions_row()],
                expanded=False,
            )
        )
        content.addStretch(1)
        self._apply_styles()

    def _settings_card(self, title: str, body: QtWidgets.QWidget) -> QtWidgets.QWidget:
        card = QtWidgets.QFrame()
        card.setObjectName("settingsCard")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(10))
        layout.addWidget(self._caption(title))
        layout.addWidget(body)
        return card

    def _expander_card(self, title: str, rows: list[QtWidgets.QWidget], *, expanded: bool) -> QtWidgets.QWidget:
        card = QtWidgets.QFrame()
        card.setObjectName("settingsCard")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(10))

        toggle = QtWidgets.QToolButton()
        toggle.setObjectName("expanderButton")
        toggle.setCheckable(True)
        toggle.setChecked(expanded)
        toggle.setToolButtonStyle(QtCore.Qt.ToolButtonTextBesideIcon)
        toggle.setArrowType(QtCore.Qt.DownArrow if expanded else QtCore.Qt.RightArrow)
        toggle.setText(title)

        body = QtWidgets.QWidget()
        body_layout = QtWidgets.QVBoxLayout(body)
        body_layout.setContentsMargins(0, 0, 0, 0)
        body_layout.setSpacing(scaled(10))
        for row in rows:
            body_layout.addWidget(row)
        body.setVisible(expanded)

        def on_toggle(checked: bool) -> None:
            toggle.setArrowType(QtCore.Qt.DownArrow if checked else QtCore.Qt.RightArrow)
            body.setVisible(checked)

        toggle.toggled.connect(on_toggle)
        layout.addWidget(toggle)
        layout.addWidget(body)
        return card

    def _caption(self, text: str) -> QtWidgets.QLabel:
        label = QtWidgets.QLabel(text)
        label.setObjectName("sectionLabel")
        return label

    def _version_row(self) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        row = QtWidgets.QHBoxLayout(host)
        row.setContentsMargins(0, 0, 0, 0)
        value = QtWidgets.QLabel(app_version())
        value.setObjectName("valuePill")
        row.addWidget(QtWidgets.QLabel("Текущая версия"))
        row.addStretch(1)
        row.addWidget(value)
        return host

    def _theme_row(self) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(scaled(8))

        group = QtWidgets.QFrame()
        group.setObjectName("segmentedGroup")
        row = QtWidgets.QHBoxLayout(group)
        row.setContentsMargins(scaled(3), scaled(3), scaled(3), scaled(3))
        row.setSpacing(scaled(4))

        self.theme_dark_button = QtWidgets.QPushButton("Тёмная")
        self.theme_dark_button.setCheckable(True)
        self.theme_dark_button.setProperty("secondary", True)
        self.theme_dark_button.clicked.connect(lambda: self.theme_changed.emit("dark"))

        self.theme_light_button = QtWidgets.QPushButton("Светлая")
        self.theme_light_button.setCheckable(True)
        self.theme_light_button.setProperty("secondary", True)
        self.theme_light_button.clicked.connect(lambda: self.theme_changed.emit("light"))

        row.addWidget(self.theme_dark_button, 1)
        row.addWidget(self.theme_light_button, 1)
        layout.addWidget(group)
        return host

    def _sleep_row(self) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(scaled(8))
        row = QtWidgets.QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.addWidget(self.prevent_sleep_checkbox)
        row.addStretch(1)
        layout.addLayout(row)
        self.prevent_sleep_hint.setObjectName("mutedBody")
        layout.addWidget(self.prevent_sleep_hint)
        return host

    def _update_row(self) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QHBoxLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(scaled(12))
        self.update_button = QtWidgets.QPushButton("Проверить обновления")
        self.update_button.setObjectName("accentButton")
        self.update_button.clicked.connect(self.update_check_requested)
        self.apply_update_button = QtWidgets.QPushButton("Установить обновление")
        self.apply_update_button.setProperty("secondary", True)
        self.apply_update_button.setVisible(False)
        self.apply_update_button.setEnabled(False)
        self.apply_update_button.clicked.connect(self.apply_update_requested)
        summary_box = QtWidgets.QVBoxLayout()
        summary_box.setContentsMargins(0, 0, 0, 0)
        summary_box.setSpacing(4)
        self.update_label.setObjectName("mutedBody")
        summary_box.addWidget(self.update_label)
        layout.addLayout(summary_box, 1)
        layout.addWidget(self.apply_update_button, 0, QtCore.Qt.AlignRight)
        layout.addWidget(self.update_button, 0, QtCore.Qt.AlignRight)
        return host

    def _instagram_grid(self) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QGridLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setHorizontalSpacing(scaled(10))
        layout.setVerticalSpacing(scaled(10))
        buttons = [
            ("Установить движок", self.bootstrap_requested, 0, 0),
            ("Проверить среду", self.refresh_requested, 0, 1),
            ("Открыть браузер для входа", self.login_requested, 1, 0),
            ("Проверить сессию", self.session_check_requested, 1, 1),
        ]
        for text, signal, row, col in buttons:
            button = QtWidgets.QPushButton(text)
            if text == "Открыть браузер для входа":
                button.setObjectName("accentButton")
            button.clicked.connect(signal)
            layout.addWidget(button, row, col)
        return host

    def _runtime_actions_row(self) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        row = QtWidgets.QHBoxLayout(host)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(scaled(10))
        button = QtWidgets.QPushButton("Открыть папку с данными")
        button.clicked.connect(self.open_runtime_requested)
        row.addStretch(1)
        row.addWidget(button)
        return host

    def _info_row(self, title: str, content: QtWidgets.QWidget) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(scaled(6))
        layout.addWidget(self._caption(title))
        if isinstance(content, QtWidgets.QLabel):
            content.setObjectName("mutedBody")
        layout.addWidget(content)
        return host

    def _apply_styles(self) -> None:
        return None

    def set_theme_value(self, theme: str) -> None:
        dark = theme != "light"
        self.theme_dark_button.setChecked(dark)
        self.theme_light_button.setChecked(not dark)

    def set_update_action_available(self, available: bool) -> None:
        self.apply_update_button.setVisible(available)
        self.apply_update_button.setEnabled(available)

    def update_state(
        self,
        *,
        worker_summary: str,
        session_summary: str,
        runtime_summary: str,
        update_summary: str,
        prevent_sleep_during_downloads: bool,
    ) -> None:
        self.update_label.setText(update_summary)
        self.worker_label.setText(worker_summary)
        self.session_label.setText(session_summary)
        self.runtime_text.setPlainText(runtime_summary)
        blocked = self.prevent_sleep_checkbox.blockSignals(True)
        self.prevent_sleep_checkbox.setChecked(prevent_sleep_during_downloads)
        self.prevent_sleep_checkbox.blockSignals(blocked)
