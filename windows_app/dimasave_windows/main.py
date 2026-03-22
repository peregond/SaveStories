from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import traceback
from datetime import datetime
import importlib.util
from pathlib import Path
from typing import Callable

from PySide6 import QtCore, QtGui, QtWidgets

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from dimasave_windows.app_paths import AppPaths
    from dimasave_windows.models import BatchEntry, WorkerRequest, WorkerResponse
    from dimasave_windows.updater import ReleaseInfo, WindowsUpdater, WindowsUpdaterError
    from dimasave_windows.worker_client import WorkerClient
else:
    from .app_paths import AppPaths
    from .models import BatchEntry, WorkerRequest, WorkerResponse
    from .updater import ReleaseInfo, WindowsUpdater, WindowsUpdaterError
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
    return "0.3.4"


def normalize_profile_link(raw: str) -> str:
    trimmed = raw.strip()
    if not trimmed:
        return trimmed
    if "instagram.com" in trimmed:
        return trimmed
    username = trimmed.strip("@/ ")
    return f"https://www.instagram.com/{username}/"


def parse_batch_links(raw: str) -> list[str]:
    links: list[str] = []
    for line in raw.splitlines():
        for part in line.split(","):
            value = part.strip()
            if value:
                links.append(normalize_profile_link(value))
    return links


def batch_status_title(value: str) -> str:
    mapping = {
        "pending": "Р’ РѕС‡РµСЂРµРґРё",
        "running": "РЎРєР°С‡РёРІР°РµС‚СЃСЏ",
        "completed": "Р“РѕС‚РѕРІРѕ",
        "failed": "РћС€РёР±РєР°",
        "stopped": "РћСЃС‚Р°РЅРѕРІР»РµРЅРѕ",
    }
    return mapping.get(value, value)


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
            env["DIMASAVE_APP_SUPPORT"] = str(AppPaths.application_support())
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


class SettingsDialog(QtWidgets.QDialog):
    refresh_requested = QtCore.Signal()
    bootstrap_requested = QtCore.Signal()
    login_requested = QtCore.Signal()
    session_check_requested = QtCore.Signal()
    open_runtime_requested = QtCore.Signal()
    update_check_requested = QtCore.Signal()

    def __init__(self, parent: QtWidgets.QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("РќР°СЃС‚СЂРѕР№РєРё")
        self.setModal(True)
        self.resize(560, 420)

        layout = QtWidgets.QVBoxLayout(self)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(14)

        title = QtWidgets.QLabel("РЎР»СѓР¶РµР±РЅС‹Рµ РЅР°СЃС‚СЂРѕР№РєРё")
        title.setObjectName("dialogTitle")
        layout.addWidget(title)

        self.worker_label = QtWidgets.QLabel("Р’РѕСЂРєРµСЂ РµС‰С‘ РЅРµ РїСЂРѕРІРµСЂСЏР»СЃСЏ.")
        self.worker_label.setWordWrap(True)
        self.session_label = QtWidgets.QLabel("РЎРѕСЃС‚РѕСЏРЅРёРµ СЃРµСЃСЃРёРё РЅРµРёР·РІРµСЃС‚РЅРѕ.")
        self.session_label.setWordWrap(True)
        self.update_label = QtWidgets.QLabel("РђРІС‚РѕРѕР±РЅРѕРІР»РµРЅРёРµ РµС‰С‘ РЅРµ РёРЅРёС†РёР°Р»РёР·РёСЂРѕРІР°РЅРѕ.")
        self.update_label.setWordWrap(True)
        self.runtime_text = QtWidgets.QPlainTextEdit()
        self.runtime_text.setReadOnly(True)
        self.runtime_text.setMinimumHeight(170)

        layout.addWidget(self._group("РћР±РЅРѕРІР»РµРЅРёСЏ", self.update_label))
        layout.addWidget(self._group("Р’РѕСЂРєРµСЂ", self.worker_label))
        layout.addWidget(self._group("РЎРµСЃСЃРёСЏ", self.session_label))
        layout.addWidget(self._group("РЎСЂРµРґР°", self.runtime_text), 1)

        button_row = QtWidgets.QHBoxLayout()
        button_row.setSpacing(10)
        for text, signal in [
            ("РЈСЃС‚Р°РЅРѕРІРёС‚СЊ РґРІРёР¶РѕРє", self.bootstrap_requested),
            ("РџСЂРѕРІРµСЂРёС‚СЊ СЃСЂРµРґСѓ", self.refresh_requested),
            ("РћС‚РєСЂС‹С‚СЊ Р±СЂР°СѓР·РµСЂ РґР»СЏ РІС…РѕРґР°", self.login_requested),
            ("РџСЂРѕРІРµСЂРёС‚СЊ СЃРµСЃСЃРёСЋ", self.session_check_requested),
            ("РџСЂРѕРІРµСЂРёС‚СЊ РѕР±РЅРѕРІР»РµРЅРёСЏ", self.update_check_requested),
            ("РћС‚РєСЂС‹С‚СЊ РїР°РїРєСѓ СЃСЂРµРґС‹", self.open_runtime_requested),
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

    def update_state(self, *, worker_summary: str, session_summary: str, runtime_summary: str, update_summary: str) -> None:
        self.update_label.setText(update_summary)
        self.worker_label.setText(worker_summary)
        self.session_label.setText(session_summary)
        self.runtime_text.setPlainText(runtime_summary)


class MainWindow(QtWidgets.QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.worker = WorkerClient()
        self.updater = WindowsUpdater()
        self.settings_store = QtCore.QSettings("DimaSave", "Windows")
        self.current_task: WorkerTask | None = None
        self.current_callback: Callable[[WorkerResponse], None] | None = None
        self.bootstrap_task: BootstrapTask | None = None
        self.update_check_task: UpdateCheckTask | None = None
        self.update_install_task: UpdateInstallTask | None = None
        self.pending_release: ReleaseInfo | None = None
        self.silent_update_check = False
        self.login_poll_timer = QtCore.QTimer(self)
        self.login_poll_timer.setInterval(3000)
        self.login_poll_timer.timeout.connect(lambda: self.check_session(startup=False))
        self.login_poll_active = False
        self.startup_login_prompt_shown = False

        self.worker_ready = False
        self.session_ready = False
        self.worker_summary = "Р’РѕСЂРєРµСЂ РµС‰С‘ РЅРµ РїСЂРѕРІРµСЂСЏР»СЃСЏ."
        self.session_summary = "РЎРѕСЃС‚РѕСЏРЅРёРµ СЃРµСЃСЃРёРё РЅРµРёР·РІРµСЃС‚РЅРѕ."
        self.runtime_summary = ""
        self.update_summary = self.updater.summary
        self.download_mode = self.settings_store.value("download_mode", "background")
        self.batch_entries: list[BatchEntry] = []
        self.batch_running = False
        self.batch_stop_requested = False
        self.batch_pending_indices: list[int] = []
        self.batch_cursor = 0
        self.batch_found_total = 0
        self.batch_saved_total = 0
        self.update_ready_to_apply = False
        self.update_download_progress = -1
        self.last_logged_update_progress = -1

        save_dir_value = self.settings_store.value("save_directory")
        self.save_directory = Path(str(save_dir_value)) if save_dir_value else AppPaths.default_downloads()
        AppPaths.ensure_directories()

        self.setWindowTitle("SaveStories for Windows")
        self.setMinimumSize(960, 620)
        default_size = QtCore.QSize(1180, 740)
        saved_geometry = self.settings_store.value("window_geometry")
        if isinstance(saved_geometry, QtCore.QByteArray) and not saved_geometry.isEmpty():
            self.restoreGeometry(saved_geometry)
        else:
            self.resize(default_size)
        self._build_ui()
        self._apply_styles()

        QtCore.QTimer.singleShot(0, self.prepare)

    def _build_ui(self) -> None:
        central = QtWidgets.QWidget()
        self.setCentralWidget(central)

        root = QtWidgets.QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        root.addWidget(self._build_sidebar())

        content_host = QtWidgets.QWidget()
        content_layout = QtWidgets.QHBoxLayout(content_host)
        content_layout.setContentsMargins(24, 24, 24, 24)
        content_layout.setSpacing(20)
        root.addWidget(content_host, 1)

        self.stack = QtWidgets.QStackedWidget()
        self.stack.addWidget(self._wrap_scroll_area(self._build_batch_page()))
        self.stack.addWidget(self._wrap_scroll_area(self._build_home_page()))
        content_layout.addWidget(self.stack, 3)

        content_layout.addWidget(self._wrap_scroll_area(self._build_activity_panel()), 2)

        self.settings_dialog = SettingsDialog(self)
        self.settings_dialog.refresh_requested.connect(self.refresh_environment)
        self.settings_dialog.bootstrap_requested.connect(self.bootstrap_environment)
        self.settings_dialog.login_requested.connect(self.login)
        self.settings_dialog.session_check_requested.connect(self.check_session)
        self.settings_dialog.update_check_requested.connect(lambda: self.check_for_updates(silent=False))
        self.settings_dialog.open_runtime_requested.connect(self.open_runtime_directory)

    def _build_sidebar(self) -> QtWidgets.QWidget:
        sidebar = QtWidgets.QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(248)

        layout = QtWidgets.QVBoxLayout(sidebar)
        layout.setContentsMargins(16, 22, 16, 16)
        layout.setSpacing(14)

        title = QtWidgets.QLabel("SaveStories")
        title.setObjectName("sidebarTitle")
        subtitle = QtWidgets.QLabel("Stories downloader")
        subtitle.setObjectName("sidebarSubtitle")
        layout.addWidget(title)
        layout.addWidget(subtitle)

        self.nav_group = QtWidgets.QButtonGroup(self)
        self.nav_group.setExclusive(True)

        for index, (text, detail) in enumerate(
            [
                ("РЎРїРёСЃРѕС‡РЅР°СЏ", "РћС‡РµСЂРµРґСЊ РїСЂРѕС„РёР»РµР№"),
                ("Р“Р»Р°РІРЅР°СЏ", "РўРµРєСѓС‰РёР№ СЂРµР¶РёРј РІС‹РіСЂСѓР·РєРё"),
            ]
        ):
            button = QtWidgets.QPushButton(f"{text}\n{detail}")
            button.setCheckable(True)
            button.setProperty("nav", True)
            button.clicked.connect(lambda checked=False, i=index: self.stack.setCurrentIndex(i))
            self.nav_group.addButton(button, index)
            layout.addWidget(button)
            if index == 0:
                button.setChecked(True)

        layout.addStretch(1)

        self.apply_update_sidebar_button = QtWidgets.QPushButton("Установить обновление")
        self.apply_update_sidebar_button.setObjectName("applyUpdateButton")
        self.apply_update_sidebar_button.setVisible(False)
        self.apply_update_sidebar_button.setEnabled(False)
        self.apply_update_sidebar_button.clicked.connect(self.apply_prepared_update)
        layout.addWidget(self.apply_update_sidebar_button)

        settings_button = QtWidgets.QPushButton("РќР°СЃС‚СЂРѕР№РєРё")
        settings_button.clicked.connect(self.open_settings)
        layout.addWidget(settings_button)

        return sidebar

    def _wrap_scroll_area(self, widget: QtWidgets.QWidget) -> QtWidgets.QScrollArea:
        area = QtWidgets.QScrollArea()
        area.setWidgetResizable(True)
        area.setFrameShape(QtWidgets.QFrame.NoFrame)
        area.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAsNeeded)
        area.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAsNeeded)
        area.setWidget(widget)
        return area

    def _build_home_page(self) -> QtWidgets.QWidget:
        page = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(18)

        layout.addWidget(self._hero("SaveStories", "Windows-РєР»РёРµРЅС‚ РґР»СЏ РІС‹РіСЂСѓР·РєРё Р°РєС‚РёРІРЅС‹С… stories РёР· Instagram РїРѕ СЃСЃС‹Р»РєРµ РЅР° РїСЂРѕС„РёР»СЊ."))
        layout.addWidget(self._status_card())
        layout.addWidget(self._save_directory_card())
        layout.addWidget(self._profile_card())
        layout.addStretch(1)
        return page

    def _build_batch_page(self) -> QtWidgets.QWidget:
        page = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(18)

        layout.addWidget(self._hero("РЎРїРёСЃРѕС‡РЅР°СЏ РІС‹РіСЂСѓР·РєР°", "Р”РѕР±Р°РІСЊ СЃСЂР°Р·Сѓ РЅРµСЃРєРѕР»СЊРєРѕ СЃСЃС‹Р»РѕРє РёР»Рё usernames. РџСЂРёР»РѕР¶РµРЅРёРµ РѕР±СЂР°Р±РѕС‚Р°РµС‚ РїСЂРѕС„РёР»Рё РїРѕ РѕС‡РµСЂРµРґРё."))

        input_card = QtWidgets.QGroupBox("Р”РѕР±Р°РІРёС‚СЊ РїСЂРѕС„РёР»Рё")
        input_layout = QtWidgets.QVBoxLayout(input_card)
        self.batch_input = QtWidgets.QPlainTextEdit()
        self.batch_input.setPlaceholderText("Р’СЃС‚Р°РІСЊ РїРѕ РѕРґРЅРѕР№ СЃСЃС‹Р»РєРµ РёР»Рё username РЅР° СЃС‚СЂРѕРєСѓ.\nРќР°РїСЂРёРјРµСЂ:\nhttps://www.instagram.com/dian.vegas1/\nmonetentony")
        self.batch_input.setFixedHeight(120)
        input_layout.addWidget(self.batch_input)

        input_buttons = QtWidgets.QHBoxLayout()
        add_button = QtWidgets.QPushButton("Р”РѕР±Р°РІРёС‚СЊ РІ РѕС‡РµСЂРµРґСЊ")
        add_button.clicked.connect(self.add_batch_profiles)
        clear_input = QtWidgets.QPushButton("РћС‡РёСЃС‚РёС‚СЊ РїРѕР»Рµ")
        clear_input.clicked.connect(self.batch_input.clear)
        input_buttons.addWidget(add_button)
        input_buttons.addWidget(clear_input)
        input_layout.addLayout(input_buttons)
        layout.addWidget(input_card)

        queue_card = QtWidgets.QGroupBox("РћС‡РµСЂРµРґСЊ РїСЂРѕС„РёР»РµР№")
        queue_layout = QtWidgets.QVBoxLayout(queue_card)
        self.batch_progress_label = QtWidgets.QLabel("РћС‡РµСЂРµРґСЊ РїРѕРєР° РїСѓСЃС‚Р°.")
        queue_layout.addWidget(self.batch_progress_label)

        self.batch_table = QtWidgets.QTableWidget(0, 3)
        self.batch_table.setHorizontalHeaderLabels(["РџСЂРѕС„РёР»СЊ", "РЎС‚Р°С‚СѓСЃ", "РЎРѕРѕР±С‰РµРЅРёРµ"])
        self.batch_table.horizontalHeader().setStretchLastSection(True)
        self.batch_table.horizontalHeader().setSectionResizeMode(0, QtWidgets.QHeaderView.Stretch)
        self.batch_table.horizontalHeader().setSectionResizeMode(1, QtWidgets.QHeaderView.ResizeToContents)
        self.batch_table.verticalHeader().setVisible(False)
        self.batch_table.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.batch_table.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.batch_table.setMinimumHeight(220)
        queue_layout.addWidget(self.batch_table)

        queue_buttons = QtWidgets.QHBoxLayout()
        self.batch_run_button = QtWidgets.QPushButton("РЎРєР°С‡Р°С‚СЊ РѕС‡РµСЂРµРґСЊ")
        self.batch_run_button.clicked.connect(self.start_batch)
        self.batch_stop_button = QtWidgets.QPushButton("РћСЃС‚Р°РЅРѕРІРёС‚СЊ")
        self.batch_stop_button.clicked.connect(self.stop_batch)
        self.batch_stop_button.setEnabled(False)
        clear_button = QtWidgets.QPushButton("РћС‡РёСЃС‚РёС‚СЊ РѕС‡РµСЂРµРґСЊ")
        clear_button.clicked.connect(self.clear_batch)
        queue_buttons.addWidget(self.batch_run_button)
        queue_buttons.addWidget(self.batch_stop_button)
        queue_buttons.addWidget(clear_button)
        queue_layout.addLayout(queue_buttons)
        layout.addWidget(queue_card)

        layout.addWidget(self._save_directory_card(batch_mode=True))
        layout.addWidget(self._mode_card(batch_mode=True))
        layout.addStretch(1)
        return page

    def _build_activity_panel(self) -> QtWidgets.QWidget:
        panel = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(18)

        title = QtWidgets.QLabel("РђРєС‚РёРІРЅРѕСЃС‚СЊ")
        title.setObjectName("panelTitle")
        self.activity_subtitle = QtWidgets.QLabel("РџРѕРєР° РЅРµС‚ РґРµР№СЃС‚РІРёР№.")
        self.activity_subtitle.setWordWrap(True)
        layout.addWidget(title)
        layout.addWidget(self.activity_subtitle)

        status_group = QtWidgets.QGroupBox("РЎС‚Р°С‚СѓСЃ Р·Р°РіСЂСѓР·РєРё")
        status_layout = QtWidgets.QVBoxLayout(status_group)
        self.status_title_label = QtWidgets.QLabel("РћР¶РёРґР°РЅРёРµ")
        self.status_title_label.setObjectName("statusTitle")
        self.status_detail_label = QtWidgets.QLabel("РџСЂРёР»РѕР¶РµРЅРёРµ РіРѕС‚РѕРІРѕ Рє СЂР°Р±РѕС‚Рµ.")
        self.status_detail_label.setWordWrap(True)
        self.found_label = QtWidgets.QLabel("РќР°Р№РґРµРЅРѕ: 0")
        self.saved_label = QtWidgets.QLabel("РЎРѕС…СЂР°РЅРµРЅРѕ: 0")
        status_layout.addWidget(self.status_title_label)
        status_layout.addWidget(self.status_detail_label)
        status_layout.addWidget(self.found_label)
        status_layout.addWidget(self.saved_label)
        layout.addWidget(status_group)

        downloads_group = QtWidgets.QGroupBox("РџРѕСЃР»РµРґРЅРёРµ Р·Р°РіСЂСѓР·РєРё")
        downloads_layout = QtWidgets.QVBoxLayout(downloads_group)
        self.downloads_list = QtWidgets.QListWidget()
        self.downloads_list.itemDoubleClicked.connect(self.open_download_item)
        downloads_layout.addWidget(self.downloads_list)
        layout.addWidget(downloads_group, 1)

        logs_group = QtWidgets.QGroupBox("Р›РѕРіРё")
        logs_layout = QtWidgets.QVBoxLayout(logs_group)
        self.logs_text = QtWidgets.QPlainTextEdit()
        self.logs_text.setReadOnly(True)
        logs_layout.addWidget(self.logs_text)
        layout.addWidget(logs_group, 1)

        return panel

    def _hero(self, title: str, subtitle: str) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)
        title_label = QtWidgets.QLabel(title)
        title_label.setObjectName("heroTitle")
        subtitle_label = QtWidgets.QLabel(subtitle)
        subtitle_label.setWordWrap(True)
        subtitle_label.setObjectName("heroSubtitle")
        version_label = QtWidgets.QLabel(f"Windows shell В· {QtWidgets.QApplication.applicationVersion() or app_version()}")
        version_label.setObjectName("heroVersion")
        layout.addWidget(title_label)
        layout.addWidget(subtitle_label)
        layout.addWidget(version_label)
        return host

    def _status_card(self) -> QtWidgets.QWidget:
        box = QtWidgets.QGroupBox("РЎРѕСЃС‚РѕСЏРЅРёРµ")
        layout = QtWidgets.QVBoxLayout(box)
        self.home_worker_summary = QtWidgets.QLabel(self.worker_summary)
        self.home_worker_summary.setWordWrap(True)
        self.home_session_summary = QtWidgets.QLabel(self.session_summary)
        self.home_session_summary.setWordWrap(True)
        layout.addWidget(QtWidgets.QLabel("Р’РѕСЂРєРµСЂ"))
        layout.addWidget(self.home_worker_summary)
        layout.addWidget(QtWidgets.QLabel("РЎРµСЃСЃРёСЏ"))
        layout.addWidget(self.home_session_summary)
        return box

    def _save_directory_card(self, *, batch_mode: bool = False) -> QtWidgets.QWidget:
        box = QtWidgets.QGroupBox("РџР°РїРєР° СЃРѕС…СЂР°РЅРµРЅРёСЏ")
        layout = QtWidgets.QVBoxLayout(box)
        line_edit = QtWidgets.QLineEdit(str(self.save_directory))
        line_edit.setReadOnly(True)
        layout.addWidget(line_edit)

        button_row = QtWidgets.QHBoxLayout()
        choose = QtWidgets.QPushButton("Р’С‹Р±СЂР°С‚СЊ РїР°РїРєСѓ")
        choose.clicked.connect(lambda: self.choose_save_directory(line_edit))
        show = QtWidgets.QPushButton("РџРѕРєР°Р·Р°С‚СЊ")
        show.clicked.connect(self.open_save_directory)
        button_row.addWidget(choose)
        button_row.addWidget(show)
        layout.addLayout(button_row)

        if batch_mode:
            self.batch_directory_line = line_edit
        else:
            self.directory_line = line_edit
        return box

    def _profile_card(self) -> QtWidgets.QWidget:
        box = QtWidgets.QGroupBox("РЎСЃС‹Р»РєР° РЅР° РїСЂРѕС„РёР»СЊ")
        layout = QtWidgets.QVBoxLayout(box)

        self.profile_input = QtWidgets.QLineEdit()
        self.profile_input.setPlaceholderText("https://www.instagram.com/username/")
        layout.addWidget(self.profile_input)
        layout.addWidget(self._mode_card())

        button = QtWidgets.QPushButton("РЎРєР°С‡Р°С‚СЊ Р°РєС‚РёРІРЅС‹Рµ stories")
        button.clicked.connect(self.download_profile)
        layout.addWidget(button)
        return box

    def _mode_card(self, *, batch_mode: bool = False) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        label = QtWidgets.QLabel("Р РµР¶РёРј РІС‹РіСЂСѓР·РєРё")
        label.setObjectName("sectionLabel")
        combo = QtWidgets.QComboBox()
        combo.addItem("Р’ С„РѕРЅРµ", "background")
        combo.addItem("Р’РёРґРёРјРѕ", "visible")
        combo.setCurrentIndex(0 if self.download_mode == "background" else 1)
        combo.currentIndexChanged.connect(self.on_mode_changed)
        detail = QtWidgets.QLabel("Р’ С„РѕРЅРµ Р±СЂР°СѓР·РµСЂ РЅРµ РїРѕРєР°Р·С‹РІР°РµС‚СЃСЏ. Р’РёРґРёРјРѕ РѕС‚РєСЂС‹РІР°РµС‚ РѕРєРЅРѕ Chromium РІРѕ РІСЂРµРјСЏ РІС‹РіСЂСѓР·РєРё.")
        detail.setWordWrap(True)

        layout.addWidget(label)
        layout.addWidget(combo)
        layout.addWidget(detail)

        if batch_mode:
            self.batch_mode_combo = combo
        else:
            self.mode_combo = combo
        return host

    def _apply_styles(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow, QWidget {
                background: #f3f3f3;
                color: #1f1f1f;
                font-family: "Segoe UI Variable Text", "Segoe UI", "Inter", sans-serif;
                font-size: 14px;
            }
            QFrame#sidebar {
                background: #fbfbfb;
                border-right: 1px solid #e6e6e6;
            }
            QLabel#sidebarTitle { font-size: 30px; font-weight: 700; color: #0f172a; }
            QLabel#sidebarSubtitle { font-size: 11px; font-weight: 700; color: #667085; text-transform: uppercase; }
            QPushButton[nav="true"] {
                text-align: left;
                padding: 13px 14px;
                border-radius: 12px;
                border: 1px solid #00000000;
                background: transparent;
                color: #1f2937;
                font-size: 14px;
                font-weight: 600;
            }
            QPushButton[nav="true"]:hover {
                background: #f3f6fc;
                border-color: #d6e4ff;
            }
            QPushButton[nav="true"]:pressed {
                background: #e8effc;
            }
            QPushButton[nav="true"]:checked {
                background: #e7f1ff;
                border-color: #c7ddff;
                color: #0a4aa3;
            }
            QLabel#heroTitle { font-size: 33px; font-weight: 700; color: #0f172a; }
            QLabel#heroSubtitle { font-size: 16px; color: #475467; }
            QLabel#heroVersion { font-size: 12px; color: #667085; }
            QLabel#panelTitle { font-size: 30px; font-weight: 700; color: #101828; }
            QLabel#statusTitle { font-size: 23px; font-weight: 700; color: #0f172a; }
            QLabel#dialogTitle { font-size: 22px; font-weight: 700; color: #0f172a; }
            QLabel#sectionLabel { font-size: 12px; font-weight: 700; color: #667085; text-transform: uppercase; }
            QGroupBox {
                border: 1px solid #e4e7ec;
                border-radius: 12px;
                margin-top: 11px;
                background: #fcfcfd;
                font-weight: 700;
                padding: 12px 12px 10px 12px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 14px;
                padding: 0 4px;
                color: #344054;
            }
            QPushButton {
                background: #0f6cbd;
                color: white;
                border: 1px solid #0f6cbd;
                border-radius: 10px;
                padding: 10px 14px;
                font-weight: 600;
            }
            QPushButton:hover { background: #115ea3; border-color: #115ea3; }
            QPushButton:pressed { background: #0f548c; border-color: #0f548c; }
            QPushButton:disabled { background: #d0d5dd; border-color: #d0d5dd; color: #f2f4f7; }
            QPushButton#applyUpdateButton {
                background: #f59e0b;
                border-color: #f59e0b;
                color: #ffffff;
                font-weight: 700;
            }
            QPushButton#applyUpdateButton:hover {
                background: #d97706;
                border-color: #d97706;
            }
            QPushButton#applyUpdateButton:pressed {
                background: #b45309;
                border-color: #b45309;
            }
            QLineEdit, QPlainTextEdit, QListWidget, QTableWidget, QComboBox {
                background: #ffffff;
                border: 1px solid #d0d5dd;
                border-radius: 10px;
                padding: 9px 10px;
                selection-background-color: #dbeafe;
                selection-color: #0f172a;
            }
            QLineEdit:focus, QPlainTextEdit:focus, QListWidget:focus, QTableWidget:focus, QComboBox:focus {
                border: 1px solid #60a5fa;
            }
            QComboBox::drop-down { border: none; width: 24px; }
            QHeaderView::section {
                background: #f8fafc;
                border: none;
                border-bottom: 1px solid #e4e7ec;
                padding: 8px;
                font-weight: 700;
                color: #344054;
            }
            QScrollBar:vertical {
                background: #f3f3f3;
                width: 12px;
                margin: 2px;
                border-radius: 6px;
            }
            QScrollBar::handle:vertical {
                background: #c9d2dd;
                min-height: 28px;
                border-radius: 6px;
            }
            QScrollBar::handle:vertical:hover { background: #b3bfcd; }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0px;
                background: transparent;
                border: none;
            }
            """
        )

    def prepare(self) -> None:
        try:
            write_crash_log("MainWindow.prepare", "Startup UI prepare started.")
            self.append_log(f"РџРѕРґРіРѕС‚РѕРІР»РµРЅС‹ РїР°РїРєРё РїСЂРёР»РѕР¶РµРЅРёСЏ РІ {AppPaths.application_support()}.")
            self.set_status("Р“РѕС‚РѕРІРѕ", "РџСЂРёР»РѕР¶РµРЅРёРµ Р·Р°РїСѓС‰РµРЅРѕ. РђРІС‚РѕРјР°С‚РёС‡РµСЃРєРёРµ С„РѕРЅРѕРІС‹Рµ РїСЂРѕРІРµСЂРєРё РѕС‚РєР»СЋС‡РµРЅС‹.")
            self.activity_subtitle.setText("РџСЂРёР»РѕР¶РµРЅРёРµ Р·Р°РїСѓС‰РµРЅРѕ. РџСЂРѕРІРµСЂРєРё СЃСЂРµРґС‹, СЃРµСЃСЃРёРё Рё РѕР±РЅРѕРІР»РµРЅРёР№ РґРѕСЃС‚СѓРїРЅС‹ РІСЂСѓС‡РЅСѓСЋ РІ РЅР°СЃС‚СЂРѕР№РєР°С….")
            write_crash_log("MainWindow.prepare", "Startup UI prepare finished with startup background checks disabled.")
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("Startup prepare failure", details)
            self.set_status("РћС€РёР±РєР°", f"РћС€РёР±РєР° Р·Р°РїСѓСЃРєР°: {error}")
            self.append_log(f"[startup_error] {error}")

    def auto_check_for_updates(self) -> None:
        if self.login_poll_active or self.current_task is not None:
            write_crash_log("auto_check_for_updates", "Deferred because startup work is still active.")
            QtCore.QTimer.singleShot(12000, self.auto_check_for_updates)
            return
        if not self.should_check_for_updates():
            return
        self.check_for_updates(silent=True)

    def should_check_for_updates(self) -> bool:
        if not self.updater.is_available:
            return False

        last_check = str(self.settings_store.value("last_update_check_at", "") or "").strip()
        if not last_check:
            return True

        try:
            previous = datetime.fromisoformat(last_check)
        except ValueError:
            return True

        elapsed = datetime.now().astimezone() - previous
        return elapsed.total_seconds() >= 12 * 60 * 60

    def startup_probe(self) -> None:
        if self.current_task is not None:
            write_crash_log("startup_probe", "Skipped because another request is already active.")
            QtCore.QTimer.singleShot(2000, self.startup_probe)
            return
        self.append_log("Р—Р°РїСѓСЃРєР°СЋ РѕС‚Р»РѕР¶РµРЅРЅСѓСЋ РїСЂРѕРІРµСЂРєСѓ СЃСЂРµРґС‹ Рё Instagram-СЃРµСЃСЃРёРё.")
        self.refresh_environment(startup=True)

    def refresh_environment(self, *, startup: bool = False) -> None:
        self.start_request(
            WorkerRequest(command="environment", urls=None),
            "РџСЂРѕРІРµСЂРєР° СЃСЂРµРґС‹ РІРѕСЂРєРµСЂР°",
            callback=lambda response: self.handle_environment_response(response, startup=startup),
        )

    def handle_environment_response(self, response: WorkerResponse, *, startup: bool = False) -> None:
        self.apply_response(response)
        self.worker_ready = response.ok
        self.worker_summary = response.message
        self.home_worker_summary.setText(self.worker_summary)
        self.runtime_summary = self.build_runtime_summary(response)
        self.settings_dialog.update_state(
            worker_summary=self.worker_summary,
            session_summary=self.session_summary,
            runtime_summary=self.runtime_summary,
            update_summary=self.update_summary,
        )
        if startup and response.ok:
            self.check_session(startup=True)

    def build_runtime_summary(self, response: WorkerResponse) -> str:
        lines = [
            f"app_support={AppPaths.application_support()}",
            f"worker_runtime={response.data.get('runtime', 'node')}",
            f"executable={response.data.get('node') or response.data.get('python') or (AppPaths.node_executable() if AppPaths.has_embedded_runtime() else AppPaths.worker_python())}",
            f"profile={response.data.get('browserProfile', str(AppPaths.browser_profile()))}",
            f"browsers={response.data.get('playwrightBrowsers', str(AppPaths.playwright_browsers()))}",
            f"manifests={response.data.get('manifests', str(AppPaths.manifests_directory()))}",
            f"default_downloads={AppPaths.default_downloads()}",
        ]
        return "\n".join(lines)

    def bootstrap_environment(self) -> None:
        if AppPaths.has_embedded_runtime():
            self.set_status("Р“РѕС‚РѕРІРѕ", "Р’ СЌС‚РѕР№ Windows-СЃР±РѕСЂРєРµ РґРІРёР¶РѕРє СѓР¶Рµ РІСЃС‚СЂРѕРµРЅ. Р”РѕРїРѕР»РЅРёС‚РµР»СЊРЅР°СЏ СѓСЃС‚Р°РЅРѕРІРєР° РЅРµ РЅСѓР¶РЅР°.")
            self.append_log("Bundled Windows runtime already available.")
            self.refresh_environment()
            return

        if self.bootstrap_task is not None and self.bootstrap_task.isRunning():
            return

        self.set_status("РџРѕРґРіРѕС‚РѕРІРєР° СЃСЂРµРґС‹ РІРѕСЂРєРµСЂР°", "РРґС‘С‚ СѓСЃС‚Р°РЅРѕРІРєР° Playwright Рё Chromium...")
        self.bootstrap_task = BootstrapTask()
        self.bootstrap_task.finished_output.connect(self.handle_bootstrap_finished)
        self.bootstrap_task.start()

    def handle_bootstrap_finished(self, ok: bool, output: str) -> None:
        self.bootstrap_task = None
        if output:
            for line in output.splitlines():
                self.append_log(line)
        self.set_status("Р“РѕС‚РѕРІРѕ" if ok else "РћС€РёР±РєР°", output or ("РЎСЂРµРґР° РїРѕРґРіРѕС‚РѕРІР»РµРЅР°." if ok else "РќРµ СѓРґР°Р»РѕСЃСЊ РїРѕРґРіРѕС‚РѕРІРёС‚СЊ СЃСЂРµРґСѓ."))
        self.refresh_environment()

    def login(self) -> None:
        try:
            self.worker.start_detached_login(
                WorkerRequest(command="login", urls=None, outputDirectory=str(self.save_directory), headless=False)
            )
            self.login_poll_active = True
            if not self.login_poll_timer.isActive():
                self.login_poll_timer.start()
            self.set_status("Р’С…РѕРґ РІ Instagram", "РћРєРЅРѕ Р±СЂР°СѓР·РµСЂР° РѕС‚РєСЂС‹С‚Рѕ. РћР¶РёРґР°СЋ РїРѕСЏРІР»РµРЅРёСЏ СЃРѕС…СЂР°РЅС‘РЅРЅРѕР№ СЃРµСЃСЃРёРё.")
            self.activity_subtitle.setText("Р’С‹РїРѕР»РЅРё РІС…РѕРґ РІ Instagram РІ РѕС‚РєСЂС‹С‚РѕРј РѕРєРЅРµ Р±СЂР°СѓР·РµСЂР°. РџСЂРёР»РѕР¶РµРЅРёРµ СЃР°РјРѕ РѕР±РЅР°СЂСѓР¶РёС‚ СЃРѕС…СЂР°РЅС‘РЅРЅСѓСЋ СЃРµСЃСЃРёСЋ.")
            self.append_log("РћС‚РєСЂС‹Р» РѕС‚РґРµР»СЊРЅРѕРµ РѕРєРЅРѕ Р±СЂР°СѓР·РµСЂР° РґР»СЏ РІС…РѕРґР° РІ Instagram.")
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("Detached login launch failure", details)
            self.set_status("РћС€РёР±РєР°", f"РќРµ СѓРґР°Р»РѕСЃСЊ РѕС‚РєСЂС‹С‚СЊ Р±СЂР°СѓР·РµСЂ РґР»СЏ РІС…РѕРґР°: {error}")
            self.append_log(f"[login_launch_error] {error}")

    def check_session(self, *, startup: bool = False) -> None:
        if self.current_task is not None:
            return
        self.start_request(
            WorkerRequest(command="check_session", urls=None, headless=True),
            "РџСЂРѕРІРµСЂРєР° СЃРѕС…СЂР°РЅС‘РЅРЅРѕР№ СЃРµСЃСЃРёРё",
            callback=lambda response: self.handle_session_response(response, startup=startup),
        )

    def handle_session_response(self, response: WorkerResponse, *, startup: bool = False) -> None:
        self.apply_response(response)
        self.session_ready = response.ok and response.data.get("loggedIn") == "true"
        self.session_summary = response.message
        self.home_session_summary.setText(self.session_summary)
        self.settings_dialog.update_state(
            worker_summary=self.worker_summary,
            session_summary=self.session_summary,
            runtime_summary=self.runtime_summary,
            update_summary=self.update_summary,
        )

        if self.session_ready and self.login_poll_active:
            self.login_poll_active = False
            self.login_poll_timer.stop()
            self.append_log("РЎРµСЃСЃРёСЏ Instagram РЅР°Р№РґРµРЅР°. РћРєРЅРѕ РІС…РѕРґР° РјРѕР¶РЅРѕ Р·Р°РєСЂС‹С‚СЊ.")
            self.set_status("Р“РѕС‚РѕРІРѕ", "РЎРµСЃСЃРёСЏ Instagram СѓСЃРїРµС€РЅРѕ СЃРѕС…СЂР°РЅРµРЅР°.")
            self.activity_subtitle.setText("РЎРµСЃСЃРёСЏ Instagram РЅР°Р№РґРµРЅР°. РџСЂРёР»РѕР¶РµРЅРёРµ РіРѕС‚РѕРІРѕ Рє РІС‹РіСЂСѓР·РєРµ.")
            return

        if startup and not self.session_ready:
            self.set_status("РќСѓР¶РµРЅ РІС…РѕРґ", "РЎРµСЃСЃРёСЏ Instagram РЅРµ РЅР°Р№РґРµРЅР°. РњРѕР¶РЅРѕ РѕС‚РєСЂС‹С‚СЊ Р±СЂР°СѓР·РµСЂ РґР»СЏ РІС…РѕРґР°.")
            self.activity_subtitle.setText("РЎРµСЃСЃРёСЏ РЅРµ РЅР°Р№РґРµРЅР°. РЎРµР№С‡Р°СЃ РїСЂРµРґР»РѕР¶Сѓ РѕС‚РєСЂС‹С‚СЊ Р±СЂР°СѓР·РµСЂ РґР»СЏ Р°РІС‚РѕСЂРёР·Р°С†РёРё.")
            self.append_log("РЎРµСЃСЃРёСЏ Instagram РЅРµ РЅР°Р№РґРµРЅР°. РџРѕРєР°Р·С‹РІР°СЋ Р±РµР·РѕРїР°СЃРЅС‹Р№ prompt РґР»СЏ РІС…РѕРґР°.")
            if not self.startup_login_prompt_shown:
                self.startup_login_prompt_shown = True
                QtCore.QTimer.singleShot(350, self.prompt_startup_login)
        elif self.login_poll_active and not self.session_ready:
            self.activity_subtitle.setText("РћР¶РёРґР°СЋ Р·Р°РІРµСЂС€РµРЅРёСЏ РІС…РѕРґР° РІ Instagram РІ РѕС‚РґРµР»СЊРЅРѕРј РѕРєРЅРµ Р±СЂР°СѓР·РµСЂР°.")

    def prompt_startup_login(self) -> None:
        write_crash_log("prompt_startup_login", "Showing startup login prompt.")
        dialog = QtWidgets.QMessageBox(self)
        dialog.setWindowTitle("РќСѓР¶РµРЅ РІС…РѕРґ РІ Instagram")
        dialog.setIcon(QtWidgets.QMessageBox.Information)
        dialog.setText("РЎРѕС…СЂР°РЅС‘РЅРЅР°СЏ Instagram-СЃРµСЃСЃРёСЏ РЅРµ РЅР°Р№РґРµРЅР°.")
        dialog.setInformativeText("РћС‚РєСЂС‹С‚СЊ РѕС‚РґРµР»СЊРЅРѕРµ РѕРєРЅРѕ Р±СЂР°СѓР·РµСЂР° РґР»СЏ РІС…РѕРґР° СЃРµР№С‡Р°СЃ?")
        open_button = dialog.addButton("РћС‚РєСЂС‹С‚СЊ Р±СЂР°СѓР·РµСЂ", QtWidgets.QMessageBox.AcceptRole)
        dialog.addButton("РџРѕР·Р¶Рµ", QtWidgets.QMessageBox.RejectRole)
        dialog.exec()
        if dialog.clickedButton() == open_button:
            self.login()
        else:
            self.append_log("Р’С…РѕРґ РІ Instagram РѕС‚Р»РѕР¶РµРЅ РїРѕР»СЊР·РѕРІР°С‚РµР»РµРј.")
            self.activity_subtitle.setText("Р’С…РѕРґ РјРѕР¶РЅРѕ РІС‹РїРѕР»РЅРёС‚СЊ РїРѕР·Р¶Рµ С‡РµСЂРµР· РєРЅРѕРїРєСѓ РІ РЅР°СЃС‚СЂРѕР№РєР°С….")

    def check_for_updates(self, *, silent: bool) -> None:
        if not self.updater.is_available:
            if not silent:
                self.append_log("РђРІС‚РѕРѕР±РЅРѕРІР»РµРЅРёРµ РЅРµРґРѕСЃС‚СѓРїРЅРѕ: РЅРµ РЅР°СЃС‚СЂРѕРµРЅ РёСЃС‚РѕС‡РЅРёРє release API.")
            return

        if self.update_check_task is not None and self.update_check_task.isRunning():
            return

        self.silent_update_check = silent
        if not silent:
            self.set_status("РџСЂРѕРІРµСЂРєР° РѕР±РЅРѕРІР»РµРЅРёР№", "Р—Р°РїСЂР°С€РёРІР°СЋ latest release РІ GitHub.")
        self.update_check_task = UpdateCheckTask(self.updater, app_version())
        self.update_check_task.finished_output.connect(self.handle_update_check_result)
        self.update_check_task.start()

    def handle_update_check_result(self, ok: bool, status: str, release: object) -> None:
        self.update_check_task = None
        self.settings_store.setValue("last_update_check_at", datetime.now().astimezone().isoformat())

        if not ok:
            self.update_summary = f"РћС€РёР±РєР° РїСЂРѕРІРµСЂРєРё РѕР±РЅРѕРІР»РµРЅРёР№: {status}"
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
            )
            if not self.silent_update_check:
                self.set_status("РћС€РёР±РєР°", status)
                self.append_log(f"[update_error] {status}")
            return

        if status == "disabled":
            self.update_summary = "РђРІС‚РѕРѕР±РЅРѕРІР»РµРЅРёРµ РЅРµ РЅР°СЃС‚СЂРѕРµРЅРѕ РґР»СЏ СЌС‚РѕР№ Windows-СЃР±РѕСЂРєРё."
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
            )
            return

        if status == "up_to_date":
            self.update_summary = f"РЈР¶Рµ СѓСЃС‚Р°РЅРѕРІР»РµРЅР° Р°РєС‚СѓР°Р»СЊРЅР°СЏ РІРµСЂСЃРёСЏ {app_version()}."
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
            )
            if not self.silent_update_check:
                self.set_status("Р“РѕС‚РѕРІРѕ", "РќРѕРІР°СЏ РІРµСЂСЃРёСЏ РЅРµ РЅР°Р№РґРµРЅР°.")
                self.append_log("РќРѕРІР°СЏ Windows-РІРµСЂСЃРёСЏ РЅРµ РЅР°Р№РґРµРЅР°.")
            return

        if status == "update_available" and isinstance(release, ReleaseInfo):
            self.pending_release = release
            self.update_summary = f"Р”РѕСЃС‚СѓРїРЅР° РІРµСЂСЃРёСЏ {release.version}. Р“РѕС‚РѕРІР° Рє СѓСЃС‚Р°РЅРѕРІРєРµ РїРѕРІРµСЂС… С‚РµРєСѓС‰РµР№ СЃР±РѕСЂРєРё."
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
            )
            self.append_log(f"РќР°Р№РґРµРЅР° РЅРѕРІР°СЏ РІРµСЂСЃРёСЏ Windows: {release.version}.")
            if self.silent_update_check:
                self.append_log("РђРІС‚РѕРїСЂРѕРІРµСЂРєР°: РѕР±РЅРѕРІР»РµРЅРёРµ РЅР°Р№РґРµРЅРѕ. РЈСЃС‚Р°РЅРѕРІРєР° РґРѕСЃС‚СѓРїРЅР° С‚РѕР»СЊРєРѕ РІСЂСѓС‡РЅСѓСЋ С‡РµСЂРµР· РЅР°СЃС‚СЂРѕР№РєРё.")
                return
            self.prompt_update_install(release)

    def prompt_update_install(self, release: ReleaseInfo) -> None:
        dialog = QtWidgets.QMessageBox(self)
        dialog.setWindowTitle("Р”РѕСЃС‚СѓРїРЅРѕ РѕР±РЅРѕРІР»РµРЅРёРµ")
        dialog.setIcon(QtWidgets.QMessageBox.Information)
        dialog.setText(f"Р”РѕСЃС‚СѓРїРЅР° РЅРѕРІР°СЏ РІРµСЂСЃРёСЏ SaveStories {release.version}.")
        details = release.notes.strip() or "GitHub release РѕРїСѓР±Р»РёРєРѕРІР°РЅ Р±РµР· release notes."
        dialog.setInformativeText("РЎРµР№С‡Р°СЃ РјРѕР¶РЅРѕ СЃРєР°С‡Р°С‚СЊ РѕР±РЅРѕРІР»РµРЅРёРµ Рё РїРµСЂРµР·Р°РїСѓСЃС‚РёС‚СЊ РїСЂРёР»РѕР¶РµРЅРёРµ.")
        dialog.setDetailedText(details)
        install_button = dialog.addButton("РЈСЃС‚Р°РЅРѕРІРёС‚СЊ", QtWidgets.QMessageBox.AcceptRole)
        dialog.addButton("РџРѕР·Р¶Рµ", QtWidgets.QMessageBox.RejectRole)
        dialog.exec()
        if dialog.clickedButton() == install_button:
            self.install_update(release, initiated_by_user=True)

    def install_update(self, release: ReleaseInfo, *, initiated_by_user: bool = False) -> None:
        if not initiated_by_user:
            self.append_log("Р—Р°РїСѓСЃРє СѓСЃС‚Р°РЅРѕРІРєРё РѕР±РЅРѕРІР»РµРЅРёСЏ Р±РµР· РїРѕРґС‚РІРµСЂР¶РґРµРЅРёСЏ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅ.")
            return

        if self.update_install_task is not None and self.update_install_task.isRunning():
            return

        self.update_ready_to_apply = False
        self.apply_update_sidebar_button.setVisible(False)
        self.apply_update_sidebar_button.setEnabled(False)
        self.set_status("РћР±РЅРѕРІР»РµРЅРёРµ", f"РЎРєР°С‡РёРІР°СЋ SaveStories {release.version} Рё РїРѕРґРіРѕС‚Р°РІР»РёРІР°СЋ Р·Р°РјРµРЅСѓ С„Р°Р№Р»РѕРІ.")
        self.append_log(f"РќР°С‡РёРЅР°СЋ СѓСЃС‚Р°РЅРѕРІРєСѓ РѕР±РЅРѕРІР»РµРЅРёСЏ Windows: {release.version}.")
        self.update_download_progress = 0
        self.last_logged_update_progress = -1
        self.update_install_task = UpdateInstallTask(self.updater, release)
        self.update_install_task.progress_output.connect(self.handle_update_install_progress)
        self.update_install_task.finished_output.connect(self.handle_update_install_result)
        self.update_install_task.start()

    def handle_update_install_progress(self, percent: int, message: str) -> None:
        self.update_download_progress = percent
        self.set_status("РћР±РЅРѕРІР»РµРЅРёРµ", message)
        if percent in {0, 100} or percent >= self.last_logged_update_progress + 10:
            self.last_logged_update_progress = percent
            self.append_log(message)

    def handle_update_install_result(self, ok: bool, message: str) -> None:
        self.update_install_task = None
        if not ok:
            self.set_status("РћС€РёР±РєР°", message)
            self.append_log(f"[update_install_error] {message}")
            return

        self.update_ready_to_apply = True
        self.apply_update_sidebar_button.setVisible(True)
        self.apply_update_sidebar_button.setEnabled(True)
        self.set_status("РћР±РЅРѕРІР»РµРЅРёРµ", message)
        self.append_log(message)
        self.append_log("Кнопка «Установить обновление» появилась в левом меню над «Настройки».")
        self.append_log("РћР±РЅРѕРІР»РµРЅРёРµ РїРѕРґРіРѕС‚РѕРІР»РµРЅРѕ. РџРµСЂРµР·Р°РїСѓСЃС‚Рё РїСЂРёР»РѕР¶РµРЅРёРµ РІСЂСѓС‡РЅСѓСЋ, РєРѕРіРґР° Р±СѓРґРµС‚ СѓРґРѕР±РЅРѕ.")

    def apply_prepared_update(self) -> None:
        if not self.update_ready_to_apply:
            self.append_log("Обновление ещё не готово к установке.")
            return

        try:
            log_path = self.updater.launch_prepared_install()
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("apply_prepared_update failure", details)
            self.set_status("Ошибка", str(error))
            self.append_log(f"[update_launch_error] {error}")
            return

        self.set_status("Обновление", "Запускаю установку обновления...")
        self.append_log(f"Запуск установки обновления. Лог: {log_path}")
        QtCore.QTimer.singleShot(150, QtWidgets.QApplication.instance().quit)

    def download_profile(self) -> None:
        profile = self.profile_input.text().strip()
        if not profile:
            self.append_log("РЎСЃС‹Р»РєР° РЅР° РїСЂРѕС„РёР»СЊ РїСѓСЃС‚Р°СЏ.")
            return

        self.start_request(
            WorkerRequest(
                command="download_profile_stories",
                url=normalize_profile_link(profile),
                urls=None,
                outputDirectory=str(self.save_directory),
                headless=self.current_headless(),
            ),
            "РЎРєР°С‡РёРІР°РЅРёРµ Р°РєС‚РёРІРЅС‹С… stories",
            callback=self.handle_download_response,
        )

    def start_batch(self) -> None:
        if self.batch_running:
            return

        pending = [index for index, item in enumerate(self.batch_entries) if item.status in {"pending", "failed"}]
        if not pending:
            self.append_log("Р’ РѕС‡РµСЂРµРґРё РЅРµС‚ РїСЂРѕС„РёР»РµР№ РґР»СЏ РїР°РєРµС‚РЅРѕР№ РІС‹РіСЂСѓР·РєРё.")
            return

        self.batch_running = True
        self.batch_stop_requested = False
        self.batch_pending_indices = pending
        self.batch_cursor = 1
        self.batch_found_total = 0
        self.batch_saved_total = 0
        self.batch_run_button.setEnabled(False)
        self.batch_stop_button.setEnabled(True)
        total = len(self.batch_pending_indices)
        remaining = max(total - 1, 0)
        self.batch_progress_label.setText(
            f"РЎРµР№С‡Р°СЃ 1 РёР· {total}, РѕСЃС‚Р°Р»РѕСЃСЊ {remaining}. РћС‡РµСЂРµРґСЊ РІС‹РїРѕР»РЅСЏРµС‚СЃСЏ РІ РѕРґРЅРѕРј РѕРєРЅРµ Р±СЂР°СѓР·РµСЂР°."
        )

        for index in self.batch_pending_indices:
            self.batch_entries[index].status = "running"
            self.batch_entries[index].message = "РћР¶РёРґР°РµС‚ РѕР±СЂР°Р±РѕС‚РєРё РІ РѕР±С‰РµРј РѕРєРЅРµ Р±СЂР°СѓР·РµСЂР°."
        self.refresh_batch_table()

        self.start_request(
            WorkerRequest(
                command="download_profile_batch",
                url=None,
                urls=[normalize_profile_link(self.batch_entries[index].url) for index in self.batch_pending_indices],
                outputDirectory=str(self.save_directory),
                headless=self.current_headless(),
            ),
            "РџР°РєРµС‚РЅР°СЏ РІС‹РіСЂСѓР·РєР°",
            callback=self.handle_batch_response,
        )

    def handle_batch_response(self, response: WorkerResponse) -> None:
        self.apply_response(response)
        if response.status == "cancelled":
            for index in self.batch_pending_indices:
                self.batch_entries[index].status = "stopped"
                self.batch_entries[index].message = "РџР°РєРµС‚РЅР°СЏ РІС‹РіСЂСѓР·РєР° РѕСЃС‚Р°РЅРѕРІР»РµРЅР° РїРѕР»СЊР·РѕРІР°С‚РµР»РµРј."
            self.batch_stop_requested = True
        else:
            self.apply_batch_results(response)

        self.batch_found_total = int(response.data.get("foundCount", str(len(response.items))) or 0)
        self.batch_saved_total = int(response.data.get("savedCount", str(len(response.items))) or 0)
        self.refresh_batch_table()
        self.finish_batch()

    def apply_batch_results(self, response: WorkerResponse) -> None:
        raw = response.data.get("batchResults", "")
        if not raw:
            for index in self.batch_pending_indices:
                self.batch_entries[index].status = "completed" if response.ok else "failed"
                self.batch_entries[index].message = response.message
            return

        try:
            payload = json.loads(raw)
        except Exception:
            for index in self.batch_pending_indices:
                self.batch_entries[index].status = "completed" if response.ok else "failed"
                self.batch_entries[index].message = response.message
            return

        result_map = {normalize_profile_link(str(item.get("url", ""))): item for item in payload if isinstance(item, dict)}
        for index in self.batch_pending_indices:
            entry = self.batch_entries[index]
            result = result_map.get(normalize_profile_link(entry.url))
            if result is None:
                entry.status = "failed"
                entry.message = "Р”Р»СЏ РїСЂРѕС„РёР»СЏ РЅРµС‚ СЂРµР·СѓР»СЊС‚Р°С‚Р° РїР°РєРµС‚РЅРѕР№ РІС‹РіСЂСѓР·РєРё."
                continue
            entry.status = "completed" if result.get("status") == "completed" else "failed"
            entry.message = str(result.get("message", response.message))

    def finish_batch(self) -> None:
        processed = len(self.batch_pending_indices)
        total = len(self.batch_pending_indices)
        if self.batch_stop_requested:
            self.set_status("РћСЃС‚Р°РЅРѕРІР»РµРЅРѕ", f"РџР°РєРµС‚РЅР°СЏ РІС‹РіСЂСѓР·РєР° РѕСЃС‚Р°РЅРѕРІР»РµРЅР°. РћР±СЂР°Р±РѕС‚Р°РЅРѕ {processed} РёР· {total}.")
        else:
            self.set_status("Р“РѕС‚РѕРІРѕ", f"РџР°РєРµС‚РЅР°СЏ РІС‹РіСЂСѓР·РєР° Р·Р°РІРµСЂС€РµРЅР°. РЎРѕС…СЂР°РЅРµРЅРѕ С„Р°Р№Р»РѕРІ: {self.batch_saved_total}.")
        self.batch_running = False
        self.batch_stop_requested = False
        self.batch_pending_indices = []
        self.batch_cursor = 0
        self.batch_progress_label.setText("РћС‡РµСЂРµРґСЊ РіРѕС‚РѕРІР°.")
        self.batch_run_button.setEnabled(True)
        self.batch_stop_button.setEnabled(False)

    def stop_batch(self) -> None:
        if not self.batch_running:
            return
        self.batch_stop_requested = True
        self.worker.stop_current_process()
        self.set_status("РћСЃС‚Р°РЅРѕРІРєР°", "РћСЃС‚Р°РЅР°РІР»РёРІР°СЋ С‚РµРєСѓС‰СѓСЋ РІС‹РіСЂСѓР·РєСѓ...")
        self.append_log("Р—Р°РїСЂРѕС€РµРЅР° РѕСЃС‚Р°РЅРѕРІРєР° РїР°РєРµС‚РЅРѕР№ РІС‹РіСЂСѓР·РєРё.")

    def add_batch_profiles(self) -> None:
        new_links = parse_batch_links(self.batch_input.toPlainText())
        if not new_links:
            self.append_log("Р”Р»СЏ РѕС‡РµСЂРµРґРё РЅРµ РЅР°Р№РґРµРЅРѕ РЅРё РѕРґРЅРѕР№ СЃСЃС‹Р»РєРё РЅР° РїСЂРѕС„РёР»СЊ.")
            return

        existing = {item.url for item in self.batch_entries}
        added = 0
        for link in new_links:
            if link in existing:
                continue
            existing.add(link)
            self.batch_entries.append(BatchEntry(url=link))
            added += 1

        self.batch_input.clear()
        self.refresh_batch_table()
        self.batch_progress_label.setText(f"Р’ РѕС‡РµСЂРµРґРё РїСЂРѕС„РёР»РµР№: {len(self.batch_entries)}.")
        self.append_log(f"Р’ РѕС‡РµСЂРµРґСЊ РґРѕР±Р°РІР»РµРЅРѕ РїСЂРѕС„РёР»РµР№: {added}.")

    def clear_batch(self) -> None:
        if self.batch_running:
            return
        self.batch_entries = []
        self.refresh_batch_table()
        self.batch_progress_label.setText("РћС‡РµСЂРµРґСЊ РїРѕРєР° РїСѓСЃС‚Р°.")
        self.append_log("РћС‡РµСЂРµРґСЊ РѕС‡РёС‰РµРЅР°.")

    def refresh_batch_table(self) -> None:
        self.batch_table.setRowCount(len(self.batch_entries))
        for row, entry in enumerate(self.batch_entries):
            self.batch_table.setItem(row, 0, QtWidgets.QTableWidgetItem(entry.url))
            self.batch_table.setItem(row, 1, QtWidgets.QTableWidgetItem(batch_status_title(entry.status)))
            self.batch_table.setItem(row, 2, QtWidgets.QTableWidgetItem(entry.message))

    def choose_save_directory(self, line_edit: QtWidgets.QLineEdit) -> None:
        directory = QtWidgets.QFileDialog.getExistingDirectory(self, "Р’С‹Р±СЂР°С‚СЊ РїР°РїРєСѓ", str(self.save_directory))
        if not directory:
            return
        self.save_directory = Path(directory)
        self.settings_store.setValue("save_directory", str(self.save_directory))
        line_edit.setText(str(self.save_directory))
        if hasattr(self, "batch_directory_line"):
            self.batch_directory_line.setText(str(self.save_directory))
        if hasattr(self, "directory_line"):
            self.directory_line.setText(str(self.save_directory))
        self.append_log(f"РџР°РїРєР° СЃРѕС…СЂР°РЅРµРЅРёСЏ РёР·РјРµРЅРµРЅР° РЅР° {self.save_directory}.")

    def on_mode_changed(self) -> None:
        combo = self.sender()
        if not isinstance(combo, QtWidgets.QComboBox):
            return
        self.download_mode = str(combo.currentData())
        self.settings_store.setValue("download_mode", self.download_mode)
        if hasattr(self, "mode_combo") and self.mode_combo is not combo:
            self.mode_combo.setCurrentIndex(combo.currentIndex())
        if hasattr(self, "batch_mode_combo") and self.batch_mode_combo is not combo:
            self.batch_mode_combo.setCurrentIndex(combo.currentIndex())

    def current_headless(self) -> bool:
        return self.download_mode == "background"

    def start_request(
        self,
        request: WorkerRequest,
        status_title: str,
        *,
        callback: Callable[[WorkerResponse], None] | None = None,
    ) -> None:
        if self.current_task is not None:
            return

        self.set_status(status_title, "Р’С‹РїРѕР»РЅСЏРµС‚СЃСЏ...")
        self.current_callback = callback
        self.current_task = WorkerTask(self.worker, request)
        self.current_task.response_ready.connect(self.finish_request)
        self.current_task.finished.connect(self.cleanup_request)
        self.current_task.start()

    def finish_request(self, response: WorkerResponse) -> None:
        callback = self.current_callback
        self.current_callback = None
        self.current_task = None
        try:
            if callback is not None:
                callback(response)
            else:
                self.apply_response(response)
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("finish_request failure", details)
            self.set_status("РћС€РёР±РєР°", f"РћС€РёР±РєР° UI-РѕР±СЂР°Р±РѕС‚РєРё: {error}")
            self.append_log(f"[ui_error] {error}")

    def cleanup_request(self) -> None:
        self.current_task = None

    def apply_response(self, response: WorkerResponse) -> None:
        self.set_status("Р“РѕС‚РѕРІРѕ" if response.ok else "РћС€РёР±РєР°", response.message)
        if "foundCount" in response.data:
            self.found_label.setText(f"РќР°Р№РґРµРЅРѕ: {response.data['foundCount']}")
        elif response.status.startswith("download"):
            self.found_label.setText(f"РќР°Р№РґРµРЅРѕ: {len(response.items)}")

        if "savedCount" in response.data:
            self.saved_label.setText(f"РЎРѕС…СЂР°РЅРµРЅРѕ: {response.data['savedCount']}")
        elif response.status == "download_complete":
            self.saved_label.setText(f"РЎРѕС…СЂР°РЅРµРЅРѕ: {len(response.items)}")

        self.activity_subtitle.setText(response.message)
        self.append_log(f"[{response.status}] {response.message}")
        for line in response.logs:
            self.append_log(line)
        for item in reversed(response.items):
            list_item = QtWidgets.QListWidgetItem(f"{item.mediaType.upper()}  {item.localPath}")
            list_item.setData(QtCore.Qt.UserRole, item.localPath)
            self.downloads_list.insertItem(0, list_item)

    def set_status(self, title: str, detail: str) -> None:
        self.status_title_label.setText(title)
        self.status_detail_label.setText(detail)

    def append_log(self, message: str) -> None:
        self.logs_text.appendPlainText(f"{display_now()}  {message}")
        scrollbar = self.logs_text.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())

    def open_settings(self) -> None:
        self.settings_dialog.update_state(
            worker_summary=self.worker_summary,
            session_summary=self.session_summary,
            runtime_summary=self.runtime_summary,
            update_summary=self.update_summary,
        )
        self.settings_dialog.show()
        self.settings_dialog.raise_()
        self.settings_dialog.activateWindow()

    def open_save_directory(self) -> None:
        self.open_in_explorer(self.save_directory)

    def open_runtime_directory(self) -> None:
        self.open_in_explorer(AppPaths.application_support())

    def open_download_item(self, item: QtWidgets.QListWidgetItem) -> None:
        path = item.data(QtCore.Qt.UserRole)
        if path:
            self.open_in_explorer(Path(path))

    def open_in_explorer(self, path: Path) -> None:
        if path.is_file():
            os.startfile(str(path.parent))
            return
        os.startfile(str(path))

    def closeEvent(self, event: QtGui.QCloseEvent) -> None:
        if self.login_poll_timer.isActive():
            self.login_poll_timer.stop()
        self.settings_store.setValue("window_geometry", self.saveGeometry())
        write_crash_log("MainWindow.closeEvent", "Window close requested.")
        super().closeEvent(event)


def main() -> int:
    install_global_exception_hooks()
    QtWidgets.QApplication.setApplicationName("SaveStories")
    QtWidgets.QApplication.setApplicationVersion(app_version())
    app = QtWidgets.QApplication(sys.argv)
    app.setStyle("Fusion")
    app.aboutToQuit.connect(lambda: write_crash_log("Application aboutToQuit", "Qt signalled application shutdown."))
    window = MainWindow()
    write_crash_log("MainWindow created", "Main window constructed successfully.")
    window.show()
    write_crash_log("Application start", f"Version: {app_version()}\nExecutable: {sys.executable}")
    QtCore.QTimer.singleShot(250, lambda: write_crash_log("Application heartbeat", "Event loop still alive after 250ms."))
    QtCore.QTimer.singleShot(2000, lambda: write_crash_log("Application heartbeat", "Event loop still alive after 2000ms."))
    return app.exec()


if __name__ == "__main__":
    if "--worker-bridge" in sys.argv:
        worker_path = AppPaths.worker_script()
        spec = importlib.util.spec_from_file_location("dimasave_worker_bridge", worker_path)
        if spec is None or spec.loader is None:
            raise SystemExit("РќРµ СѓРґР°Р»РѕСЃСЊ Р·Р°РіСЂСѓР·РёС‚СЊ РІСЃС‚СЂРѕРµРЅРЅС‹Р№ worker bridge.")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.main()
        raise SystemExit(0)

    raise SystemExit(main())

