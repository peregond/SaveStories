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
        "pending": "В очереди",
        "running": "Скачивается",
        "completed": "Готово",
        "failed": "Ошибка",
        "stopped": "Остановлено",
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

    def __init__(self, updater: WindowsUpdater, release: ReleaseInfo) -> None:
        super().__init__()
        self.updater = updater
        self.release = release

    def run(self) -> None:
        try:
            message = self.updater.prepare_install(self.release)
            self.finished_output.emit(True, message)
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("UpdateInstallTask failure", details)
            self.finished_output.emit(False, str(error))


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
        self.worker_summary = "Воркер ещё не проверялся."
        self.session_summary = "Состояние сессии неизвестно."
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

        save_dir_value = self.settings_store.value("save_directory")
        self.save_directory = Path(str(save_dir_value)) if save_dir_value else AppPaths.default_downloads()
        AppPaths.ensure_directories()

        self.setWindowTitle("SaveStories for Windows")
        self.setMinimumSize(1100, 720)
        self.resize(1360, 860)
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
                ("Списочная", "Очередь профилей"),
                ("Главная", "Текущий режим выгрузки"),
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

        settings_button = QtWidgets.QPushButton("Настройки")
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

        layout.addWidget(self._hero("SaveStories", "Windows-клиент для выгрузки активных stories из Instagram по ссылке на профиль."))
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

        layout.addWidget(self._hero("Списочная выгрузка", "Добавь сразу несколько ссылок или usernames. Приложение обработает профили по очереди."))

        input_card = QtWidgets.QGroupBox("Добавить профили")
        input_layout = QtWidgets.QVBoxLayout(input_card)
        self.batch_input = QtWidgets.QPlainTextEdit()
        self.batch_input.setPlaceholderText("Вставь по одной ссылке или username на строку.\nНапример:\nhttps://www.instagram.com/dian.vegas1/\nmonetentony")
        self.batch_input.setFixedHeight(120)
        input_layout.addWidget(self.batch_input)

        input_buttons = QtWidgets.QHBoxLayout()
        add_button = QtWidgets.QPushButton("Добавить в очередь")
        add_button.clicked.connect(self.add_batch_profiles)
        clear_input = QtWidgets.QPushButton("Очистить поле")
        clear_input.clicked.connect(self.batch_input.clear)
        input_buttons.addWidget(add_button)
        input_buttons.addWidget(clear_input)
        input_layout.addLayout(input_buttons)
        layout.addWidget(input_card)

        queue_card = QtWidgets.QGroupBox("Очередь профилей")
        queue_layout = QtWidgets.QVBoxLayout(queue_card)
        self.batch_progress_label = QtWidgets.QLabel("Очередь пока пуста.")
        queue_layout.addWidget(self.batch_progress_label)

        self.batch_table = QtWidgets.QTableWidget(0, 3)
        self.batch_table.setHorizontalHeaderLabels(["Профиль", "Статус", "Сообщение"])
        self.batch_table.horizontalHeader().setStretchLastSection(True)
        self.batch_table.horizontalHeader().setSectionResizeMode(0, QtWidgets.QHeaderView.Stretch)
        self.batch_table.horizontalHeader().setSectionResizeMode(1, QtWidgets.QHeaderView.ResizeToContents)
        self.batch_table.verticalHeader().setVisible(False)
        self.batch_table.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.batch_table.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.batch_table.setMinimumHeight(220)
        queue_layout.addWidget(self.batch_table)

        queue_buttons = QtWidgets.QHBoxLayout()
        self.batch_run_button = QtWidgets.QPushButton("Скачать очередь")
        self.batch_run_button.clicked.connect(self.start_batch)
        self.batch_stop_button = QtWidgets.QPushButton("Остановить")
        self.batch_stop_button.clicked.connect(self.stop_batch)
        self.batch_stop_button.setEnabled(False)
        clear_button = QtWidgets.QPushButton("Очистить очередь")
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

        title = QtWidgets.QLabel("Активность")
        title.setObjectName("panelTitle")
        self.activity_subtitle = QtWidgets.QLabel("Пока нет действий.")
        self.activity_subtitle.setWordWrap(True)
        layout.addWidget(title)
        layout.addWidget(self.activity_subtitle)

        status_group = QtWidgets.QGroupBox("Статус загрузки")
        status_layout = QtWidgets.QVBoxLayout(status_group)
        self.status_title_label = QtWidgets.QLabel("Ожидание")
        self.status_title_label.setObjectName("statusTitle")
        self.status_detail_label = QtWidgets.QLabel("Приложение готово к работе.")
        self.status_detail_label.setWordWrap(True)
        self.found_label = QtWidgets.QLabel("Найдено: 0")
        self.saved_label = QtWidgets.QLabel("Сохранено: 0")
        status_layout.addWidget(self.status_title_label)
        status_layout.addWidget(self.status_detail_label)
        status_layout.addWidget(self.found_label)
        status_layout.addWidget(self.saved_label)
        layout.addWidget(status_group)

        downloads_group = QtWidgets.QGroupBox("Последние загрузки")
        downloads_layout = QtWidgets.QVBoxLayout(downloads_group)
        self.downloads_list = QtWidgets.QListWidget()
        self.downloads_list.itemDoubleClicked.connect(self.open_download_item)
        downloads_layout.addWidget(self.downloads_list)
        layout.addWidget(downloads_group, 1)

        logs_group = QtWidgets.QGroupBox("Логи")
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
        version_label = QtWidgets.QLabel(f"Windows shell · {QtWidgets.QApplication.applicationVersion() or app_version()}")
        version_label.setObjectName("heroVersion")
        layout.addWidget(title_label)
        layout.addWidget(subtitle_label)
        layout.addWidget(version_label)
        return host

    def _status_card(self) -> QtWidgets.QWidget:
        box = QtWidgets.QGroupBox("Состояние")
        layout = QtWidgets.QVBoxLayout(box)
        self.home_worker_summary = QtWidgets.QLabel(self.worker_summary)
        self.home_worker_summary.setWordWrap(True)
        self.home_session_summary = QtWidgets.QLabel(self.session_summary)
        self.home_session_summary.setWordWrap(True)
        layout.addWidget(QtWidgets.QLabel("Воркер"))
        layout.addWidget(self.home_worker_summary)
        layout.addWidget(QtWidgets.QLabel("Сессия"))
        layout.addWidget(self.home_session_summary)
        return box

    def _save_directory_card(self, *, batch_mode: bool = False) -> QtWidgets.QWidget:
        box = QtWidgets.QGroupBox("Папка сохранения")
        layout = QtWidgets.QVBoxLayout(box)
        line_edit = QtWidgets.QLineEdit(str(self.save_directory))
        line_edit.setReadOnly(True)
        layout.addWidget(line_edit)

        button_row = QtWidgets.QHBoxLayout()
        choose = QtWidgets.QPushButton("Выбрать папку")
        choose.clicked.connect(lambda: self.choose_save_directory(line_edit))
        show = QtWidgets.QPushButton("Показать")
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
        box = QtWidgets.QGroupBox("Ссылка на профиль")
        layout = QtWidgets.QVBoxLayout(box)

        self.profile_input = QtWidgets.QLineEdit()
        self.profile_input.setPlaceholderText("https://www.instagram.com/username/")
        layout.addWidget(self.profile_input)
        layout.addWidget(self._mode_card())

        button = QtWidgets.QPushButton("Скачать активные stories")
        button.clicked.connect(self.download_profile)
        layout.addWidget(button)
        return box

    def _mode_card(self, *, batch_mode: bool = False) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        label = QtWidgets.QLabel("Режим выгрузки")
        label.setObjectName("sectionLabel")
        combo = QtWidgets.QComboBox()
        combo.addItem("В фоне", "background")
        combo.addItem("Видимо", "visible")
        combo.setCurrentIndex(0 if self.download_mode == "background" else 1)
        combo.currentIndexChanged.connect(self.on_mode_changed)
        detail = QtWidgets.QLabel("В фоне браузер не показывается. Видимо открывает окно Chromium во время выгрузки.")
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
                background: #f5f7fb;
                color: #162235;
                font-size: 14px;
            }
            QFrame#sidebar {
                background: #eef2f8;
                border-right: 1px solid #d7dfeb;
            }
            QLabel#sidebarTitle { font-size: 28px; font-weight: 700; color: #102844; }
            QLabel#sidebarSubtitle { font-size: 11px; font-weight: 700; color: #5f7289; text-transform: uppercase; }
            QPushButton[nav="true"] {
                text-align: left;
                padding: 14px;
                border-radius: 16px;
                border: 1px solid transparent;
                background: transparent;
                color: #173454;
                font-size: 14px;
                font-weight: 600;
            }
            QPushButton[nav="true"]:hover {
                background: #e5edf8;
                border-color: #d2def0;
            }
            QPushButton[nav="true"]:pressed {
                background: #dce8f8;
            }
            QPushButton[nav="true"]:checked {
                background: #d7e8ff; border-color: #b8cff7; color: #0e3f7a;
            }
            QLabel#heroTitle { font-size: 34px; font-weight: 700; color: #102844; }
            QLabel#heroSubtitle { font-size: 16px; color: #4f6279; }
            QLabel#heroVersion { font-size: 12px; color: #6f8096; }
            QLabel#panelTitle { font-size: 28px; font-weight: 700; }
            QLabel#statusTitle { font-size: 22px; font-weight: 700; }
            QLabel#dialogTitle { font-size: 22px; font-weight: 700; }
            QLabel#sectionLabel { font-size: 12px; font-weight: 700; color: #6c7d90; text-transform: uppercase; }
            QGroupBox {
                border: 1px solid #d9e2ee;
                border-radius: 14px;
                margin-top: 10px;
                background: rgba(255, 255, 255, 0.92);
                font-weight: 700;
                padding: 12px;
            }
            QGroupBox::title { subcontrol-origin: margin; left: 14px; padding: 0 4px; }
            QPushButton {
                background: #176ec8; color: white; border: 1px solid #176ec8; border-radius: 12px; padding: 10px 14px;
                font-weight: 600;
            }
            QPushButton:hover { background: #0f5ca9; border-color: #0f5ca9; }
            QPushButton:disabled { background: #c3cedc; border-color: #c3cedc; color: #eef3f9; }
            QLineEdit, QPlainTextEdit, QListWidget, QTableWidget, QComboBox {
                background: white; border: 1px solid #dbe4ef; border-radius: 12px; padding: 10px;
            }
            QHeaderView::section {
                background: #edf2f8; border: none; border-bottom: 1px solid #dbe4ef; padding: 8px; font-weight: 700;
            }
            """
        )

    def prepare(self) -> None:
        try:
            write_crash_log("MainWindow.prepare", "Startup UI prepare started.")
            self.append_log(f"Подготовлены папки приложения в {AppPaths.application_support()}.")
            self.set_status("Готово", "Приложение запущено. Автоматические фоновые проверки отключены.")
            self.activity_subtitle.setText("Приложение запущено. Проверки среды, сессии и обновлений доступны вручную в настройках.")
            write_crash_log("MainWindow.prepare", "Startup UI prepare finished with startup background checks disabled.")
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("Startup prepare failure", details)
            self.set_status("Ошибка", f"Ошибка запуска: {error}")
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
        self.append_log("Запускаю отложенную проверку среды и Instagram-сессии.")
        self.refresh_environment(startup=True)

    def refresh_environment(self, *, startup: bool = False) -> None:
        self.start_request(
            WorkerRequest(command="environment", urls=None),
            "Проверка среды воркера",
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
            self.set_status("Готово", "В этой Windows-сборке движок уже встроен. Дополнительная установка не нужна.")
            self.append_log("Bundled Windows runtime already available.")
            self.refresh_environment()
            return

        if self.bootstrap_task is not None and self.bootstrap_task.isRunning():
            return

        self.set_status("Подготовка среды воркера", "Идёт установка Playwright и Chromium...")
        self.bootstrap_task = BootstrapTask()
        self.bootstrap_task.finished_output.connect(self.handle_bootstrap_finished)
        self.bootstrap_task.start()

    def handle_bootstrap_finished(self, ok: bool, output: str) -> None:
        self.bootstrap_task = None
        if output:
            for line in output.splitlines():
                self.append_log(line)
        self.set_status("Готово" if ok else "Ошибка", output or ("Среда подготовлена." if ok else "Не удалось подготовить среду."))
        self.refresh_environment()

    def login(self) -> None:
        try:
            self.worker.start_detached_login(
                WorkerRequest(command="login", urls=None, outputDirectory=str(self.save_directory), headless=False)
            )
            self.login_poll_active = True
            if not self.login_poll_timer.isActive():
                self.login_poll_timer.start()
            self.set_status("Вход в Instagram", "Окно браузера открыто. Ожидаю появления сохранённой сессии.")
            self.activity_subtitle.setText("Выполни вход в Instagram в открытом окне браузера. Приложение само обнаружит сохранённую сессию.")
            self.append_log("Открыл отдельное окно браузера для входа в Instagram.")
        except Exception as error:
            details = "".join(traceback.format_exception(type(error), error, error.__traceback__))
            write_crash_log("Detached login launch failure", details)
            self.set_status("Ошибка", f"Не удалось открыть браузер для входа: {error}")
            self.append_log(f"[login_launch_error] {error}")

    def check_session(self, *, startup: bool = False) -> None:
        if self.current_task is not None:
            return
        self.start_request(
            WorkerRequest(command="check_session", urls=None, headless=True),
            "Проверка сохранённой сессии",
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
            self.append_log("Сессия Instagram найдена. Окно входа можно закрыть.")
            self.set_status("Готово", "Сессия Instagram успешно сохранена.")
            self.activity_subtitle.setText("Сессия Instagram найдена. Приложение готово к выгрузке.")
            return

        if startup and not self.session_ready:
            self.set_status("Нужен вход", "Сессия Instagram не найдена. Можно открыть браузер для входа.")
            self.activity_subtitle.setText("Сессия не найдена. Сейчас предложу открыть браузер для авторизации.")
            self.append_log("Сессия Instagram не найдена. Показываю безопасный prompt для входа.")
            if not self.startup_login_prompt_shown:
                self.startup_login_prompt_shown = True
                QtCore.QTimer.singleShot(350, self.prompt_startup_login)
        elif self.login_poll_active and not self.session_ready:
            self.activity_subtitle.setText("Ожидаю завершения входа в Instagram в отдельном окне браузера.")

    def prompt_startup_login(self) -> None:
        write_crash_log("prompt_startup_login", "Showing startup login prompt.")
        dialog = QtWidgets.QMessageBox(self)
        dialog.setWindowTitle("Нужен вход в Instagram")
        dialog.setIcon(QtWidgets.QMessageBox.Information)
        dialog.setText("Сохранённая Instagram-сессия не найдена.")
        dialog.setInformativeText("Открыть отдельное окно браузера для входа сейчас?")
        open_button = dialog.addButton("Открыть браузер", QtWidgets.QMessageBox.AcceptRole)
        dialog.addButton("Позже", QtWidgets.QMessageBox.RejectRole)
        dialog.exec()
        if dialog.clickedButton() is open_button:
            self.login()
        else:
            self.append_log("Вход в Instagram отложен пользователем.")
            self.activity_subtitle.setText("Вход можно выполнить позже через кнопку в настройках.")

    def check_for_updates(self, *, silent: bool) -> None:
        if not self.updater.is_available:
            if not silent:
                self.append_log("Автообновление недоступно: не настроен источник release API.")
            return

        if self.update_check_task is not None and self.update_check_task.isRunning():
            return

        self.silent_update_check = silent
        if not silent:
            self.set_status("Проверка обновлений", "Запрашиваю latest release в GitHub.")
        self.update_check_task = UpdateCheckTask(self.updater, app_version())
        self.update_check_task.finished_output.connect(self.handle_update_check_result)
        self.update_check_task.start()

    def handle_update_check_result(self, ok: bool, status: str, release: object) -> None:
        self.update_check_task = None
        self.settings_store.setValue("last_update_check_at", datetime.now().astimezone().isoformat())

        if not ok:
            self.update_summary = f"Ошибка проверки обновлений: {status}"
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
            )
            if not self.silent_update_check:
                self.set_status("Ошибка", status)
                self.append_log(f"[update_error] {status}")
            return

        if status == "disabled":
            self.update_summary = "Автообновление не настроено для этой Windows-сборки."
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
            )
            return

        if status == "up_to_date":
            self.update_summary = f"Уже установлена актуальная версия {app_version()}."
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
            )
            if not self.silent_update_check:
                self.set_status("Готово", "Новая версия не найдена.")
                self.append_log("Новая Windows-версия не найдена.")
            return

        if status == "update_available" and isinstance(release, ReleaseInfo):
            self.pending_release = release
            self.update_summary = f"Доступна версия {release.version}. Готова к установке поверх текущей сборки."
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
            )
            self.append_log(f"Найдена новая версия Windows: {release.version}.")
            if self.silent_update_check:
                self.append_log("Автопроверка: обновление найдено. Установка доступна только вручную через настройки.")
                return
            self.prompt_update_install(release)

    def prompt_update_install(self, release: ReleaseInfo) -> None:
        dialog = QtWidgets.QMessageBox(self)
        dialog.setWindowTitle("Доступно обновление")
        dialog.setIcon(QtWidgets.QMessageBox.Information)
        dialog.setText(f"Доступна новая версия SaveStories {release.version}.")
        details = release.notes.strip() or "GitHub release опубликован без release notes."
        dialog.setInformativeText("Сейчас можно скачать обновление и перезапустить приложение.")
        dialog.setDetailedText(details)
        install_button = dialog.addButton("Установить", QtWidgets.QMessageBox.AcceptRole)
        dialog.addButton("Позже", QtWidgets.QMessageBox.RejectRole)
        dialog.exec()
        if dialog.clickedButton() is install_button:
            self.install_update(release, initiated_by_user=True)

    def install_update(self, release: ReleaseInfo, *, initiated_by_user: bool = False) -> None:
        if not initiated_by_user:
            self.append_log("Запуск установки обновления без подтверждения пользователя заблокирован.")
            return

        if self.update_install_task is not None and self.update_install_task.isRunning():
            return

        self.set_status("Обновление", f"Скачиваю SaveStories {release.version} и подготавливаю замену файлов.")
        self.append_log(f"Начинаю установку обновления Windows: {release.version}.")
        self.update_install_task = UpdateInstallTask(self.updater, release)
        self.update_install_task.finished_output.connect(self.handle_update_install_result)
        self.update_install_task.start()

    def handle_update_install_result(self, ok: bool, message: str) -> None:
        self.update_install_task = None
        if not ok:
            self.set_status("Ошибка", message)
            self.append_log(f"[update_install_error] {message}")
            return

        self.set_status("Обновление", message)
        self.append_log(message)
        self.append_log("Обновление подготовлено. Перезапусти приложение вручную, когда будет удобно.")

    def download_profile(self) -> None:
        profile = self.profile_input.text().strip()
        if not profile:
            self.append_log("Ссылка на профиль пустая.")
            return

        self.start_request(
            WorkerRequest(
                command="download_profile_stories",
                url=normalize_profile_link(profile),
                urls=None,
                outputDirectory=str(self.save_directory),
                headless=self.current_headless(),
            ),
            "Скачивание активных stories",
            callback=self.handle_download_response,
        )

    def start_batch(self) -> None:
        if self.batch_running:
            return

        pending = [index for index, item in enumerate(self.batch_entries) if item.status in {"pending", "failed"}]
        if not pending:
            self.append_log("В очереди нет профилей для пакетной выгрузки.")
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
            f"Сейчас 1 из {total}, осталось {remaining}. Очередь выполняется в одном окне браузера."
        )

        for index in self.batch_pending_indices:
            self.batch_entries[index].status = "running"
            self.batch_entries[index].message = "Ожидает обработки в общем окне браузера."
        self.refresh_batch_table()

        self.start_request(
            WorkerRequest(
                command="download_profile_batch",
                url=None,
                urls=[normalize_profile_link(self.batch_entries[index].url) for index in self.batch_pending_indices],
                outputDirectory=str(self.save_directory),
                headless=self.current_headless(),
            ),
            "Пакетная выгрузка",
            callback=self.handle_batch_response,
        )

    def handle_batch_response(self, response: WorkerResponse) -> None:
        self.apply_response(response)
        if response.status == "cancelled":
            for index in self.batch_pending_indices:
                self.batch_entries[index].status = "stopped"
                self.batch_entries[index].message = "Пакетная выгрузка остановлена пользователем."
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
                entry.message = "Для профиля нет результата пакетной выгрузки."
                continue
            entry.status = "completed" if result.get("status") == "completed" else "failed"
            entry.message = str(result.get("message", response.message))

    def finish_batch(self) -> None:
        processed = len(self.batch_pending_indices)
        total = len(self.batch_pending_indices)
        if self.batch_stop_requested:
            self.set_status("Остановлено", f"Пакетная выгрузка остановлена. Обработано {processed} из {total}.")
        else:
            self.set_status("Готово", f"Пакетная выгрузка завершена. Сохранено файлов: {self.batch_saved_total}.")
        self.batch_running = False
        self.batch_stop_requested = False
        self.batch_pending_indices = []
        self.batch_cursor = 0
        self.batch_progress_label.setText("Очередь готова.")
        self.batch_run_button.setEnabled(True)
        self.batch_stop_button.setEnabled(False)

    def stop_batch(self) -> None:
        if not self.batch_running:
            return
        self.batch_stop_requested = True
        self.worker.stop_current_process()
        self.set_status("Остановка", "Останавливаю текущую выгрузку...")
        self.append_log("Запрошена остановка пакетной выгрузки.")

    def add_batch_profiles(self) -> None:
        new_links = parse_batch_links(self.batch_input.toPlainText())
        if not new_links:
            self.append_log("Для очереди не найдено ни одной ссылки на профиль.")
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
        self.batch_progress_label.setText(f"В очереди профилей: {len(self.batch_entries)}.")
        self.append_log(f"В очередь добавлено профилей: {added}.")

    def clear_batch(self) -> None:
        if self.batch_running:
            return
        self.batch_entries = []
        self.refresh_batch_table()
        self.batch_progress_label.setText("Очередь пока пуста.")
        self.append_log("Очередь очищена.")

    def refresh_batch_table(self) -> None:
        self.batch_table.setRowCount(len(self.batch_entries))
        for row, entry in enumerate(self.batch_entries):
            self.batch_table.setItem(row, 0, QtWidgets.QTableWidgetItem(entry.url))
            self.batch_table.setItem(row, 1, QtWidgets.QTableWidgetItem(batch_status_title(entry.status)))
            self.batch_table.setItem(row, 2, QtWidgets.QTableWidgetItem(entry.message))

    def choose_save_directory(self, line_edit: QtWidgets.QLineEdit) -> None:
        directory = QtWidgets.QFileDialog.getExistingDirectory(self, "Выбрать папку", str(self.save_directory))
        if not directory:
            return
        self.save_directory = Path(directory)
        self.settings_store.setValue("save_directory", str(self.save_directory))
        line_edit.setText(str(self.save_directory))
        if hasattr(self, "batch_directory_line"):
            self.batch_directory_line.setText(str(self.save_directory))
        if hasattr(self, "directory_line"):
            self.directory_line.setText(str(self.save_directory))
        self.append_log(f"Папка сохранения изменена на {self.save_directory}.")

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

        self.set_status(status_title, "Выполняется...")
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
            self.set_status("Ошибка", f"Ошибка UI-обработки: {error}")
            self.append_log(f"[ui_error] {error}")

    def cleanup_request(self) -> None:
        self.current_task = None

    def apply_response(self, response: WorkerResponse) -> None:
        self.set_status("Готово" if response.ok else "Ошибка", response.message)
        if "foundCount" in response.data:
            self.found_label.setText(f"Найдено: {response.data['foundCount']}")
        elif response.status.startswith("download"):
            self.found_label.setText(f"Найдено: {len(response.items)}")

        if "savedCount" in response.data:
            self.saved_label.setText(f"Сохранено: {response.data['savedCount']}")
        elif response.status == "download_complete":
            self.saved_label.setText(f"Сохранено: {len(response.items)}")

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
            raise SystemExit("Не удалось загрузить встроенный worker bridge.")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.main()
        raise SystemExit(0)

    raise SystemExit(main())
