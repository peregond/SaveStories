from __future__ import annotations

import json
import os
import sys
import traceback
from datetime import datetime
import importlib.util
from pathlib import Path
from typing import Callable

from PySide6 import QtCore, QtGui, QtWidgets

try:
    import winsound
except ImportError:
    winsound = None

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from savestories_windows.app_paths import AppPaths
    from savestories_windows.batch_flow import MainWindowBatchFlowMixin
    from savestories_windows.models import BatchEntry, WorkerRequest, WorkerResponse
    from savestories_windows.ui_layout import MainWindowLayoutMixin
    from savestories_windows.update_flow import MainWindowUpdateFlowMixin
    from savestories_windows.updater import ReleaseInfo, WindowsUpdater, WindowsUpdaterError
    from savestories_windows.ui_support import (
        BootstrapTask,
        ConfettiOverlay,
        SettingsDialog,
        UpdateCheckTask,
        UpdateInstallTask,
        WorkerTask,
        app_version,
        batch_status_title,
        display_now,
        install_global_exception_hooks,
        normalize_profile_link,
        parse_batch_links,
        suggested_recent_list_title,
        write_crash_log,
    )
    from savestories_windows.worker_client import WorkerClient
else:
    from .app_paths import AppPaths
    from .batch_flow import MainWindowBatchFlowMixin
    from .models import BatchEntry, WorkerRequest, WorkerResponse
    from .ui_layout import MainWindowLayoutMixin
    from .update_flow import MainWindowUpdateFlowMixin
    from .updater import ReleaseInfo, WindowsUpdater, WindowsUpdaterError
    from .ui_support import (
        BootstrapTask,
        ConfettiOverlay,
        SettingsDialog,
        UpdateCheckTask,
        UpdateInstallTask,
        WorkerTask,
        app_version,
        batch_status_title,
        display_now,
        install_global_exception_hooks,
        normalize_profile_link,
        parse_batch_links,
        suggested_recent_list_title,
        write_crash_log,
    )
    from .worker_client import WorkerClient


class MainWindow(MainWindowBatchFlowMixin, MainWindowUpdateFlowMixin, MainWindowLayoutMixin, QtWidgets.QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.worker = WorkerClient()
        self.updater = WindowsUpdater()
        self.settings_store = QtCore.QSettings("SaveStories", "Windows")
        self.migrate_legacy_settings()
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
        self.media_filter = self.settings_store.value("media_filter", "video_only")
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
        self.current_step_label = "Ожидание команды."
        self.recent_lists: list[dict[str, object]] = self.load_recent_lists()
        self.home2_recent_expanded = False
        self.live_downloaded_file_count = 0
        self.live_created_folder_count = 0
        self.status_pulse_active = False
        self._save_directory_baseline_files = 0
        self._save_directory_baseline_folders = 0
        self.live_tracking_timer = QtCore.QTimer(self)
        self.live_tracking_timer.setInterval(2000)
        self.live_tracking_timer.timeout.connect(self.refresh_live_download_tracking)
        self.status_pulse_timer = QtCore.QTimer(self)
        self.status_pulse_timer.setInterval(420)
        self.status_pulse_timer.timeout.connect(self._tick_status_pulse)

        save_dir_value = self.settings_store.value("save_directory")
        self.save_directory = Path(str(save_dir_value)) if save_dir_value else AppPaths.default_downloads()
        AppPaths.ensure_directories()
        self.reset_live_download_tracking_baseline()

        self.setWindowTitle("SaveStories for Windows")
        self.setMinimumSize(960, 620)
        default_size = QtCore.QSize(1180, 740)
        saved_geometry = self.settings_store.value("window_geometry")
        if isinstance(saved_geometry, QtCore.QByteArray) and not saved_geometry.isEmpty():
            self.restoreGeometry(saved_geometry)
        else:
            self.resize(default_size)
        self._build_ui()
        self.confetti_overlay = ConfettiOverlay(self.centralWidget())
        self._apply_styles()
        self.refresh_recent_lists_ui()
        self.refresh_home2_status_strip()

        QtCore.QTimer.singleShot(0, self.prepare)

    def migrate_legacy_settings(self) -> None:
        legacy_settings = QtCore.QSettings("DimaSave", "Windows")
        migrated = False
        for key in legacy_settings.allKeys():
            if self.settings_store.contains(key):
                continue
            self.settings_store.setValue(key, legacy_settings.value(key))
            migrated = True
        if migrated:
            self.settings_store.sync()


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
        self.refresh_home2_status_strip()
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
        self.refresh_home2_status_strip()

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
        if dialog.clickedButton() == open_button:
            self.login()
        else:
            self.append_log("Вход в Instagram отложен пользователем.")
            self.activity_subtitle.setText("Вход можно выполнить позже через кнопку в настройках.")

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
                mediaFilter=self.current_media_filter(),
            ),
            "Скачивание активных stories",
            callback=self.handle_download_response,
        )

    def choose_save_directory(self, line_edit: QtWidgets.QLineEdit) -> None:
        directory = QtWidgets.QFileDialog.getExistingDirectory(self, "Выбрать папку", str(self.save_directory))
        if not directory:
            return
        self.save_directory = Path(directory)
        self.settings_store.setValue("save_directory", str(self.save_directory))
        self.reset_live_download_tracking_baseline()
        line_edit.setText(str(self.save_directory))
        if hasattr(self, "batch_directory_line"):
            self.batch_directory_line.setText(str(self.save_directory))
        if hasattr(self, "directory_line"):
            self.directory_line.setText(str(self.save_directory))
        if hasattr(self, "home2_directory_line"):
            self.home2_directory_line.setText(str(self.save_directory))
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
        if hasattr(self, "home2_mode_combo") and self.home2_mode_combo is not combo:
            self.home2_mode_combo.setCurrentIndex(combo.currentIndex())
        if hasattr(self, "home2_mode_label"):
            self.home2_mode_label.setText(f"Режим: {'В фоне' if self.download_mode == 'background' else 'Видимо'}")

    def on_media_filter_changed(self) -> None:
        combo = self.sender()
        if not isinstance(combo, QtWidgets.QComboBox):
            return
        self.media_filter = str(combo.currentData())
        self.settings_store.setValue("media_filter", self.media_filter)
        if hasattr(self, "media_combo") and self.media_combo is not combo:
            self.media_combo.setCurrentIndex(combo.currentIndex())
        if hasattr(self, "batch_media_combo") and self.batch_media_combo is not combo:
            self.batch_media_combo.setCurrentIndex(combo.currentIndex())
        if hasattr(self, "home2_media_combo") and self.home2_media_combo is not combo:
            self.home2_media_combo.setCurrentIndex(combo.currentIndex())
        if hasattr(self, "home2_media_label"):
            self.home2_media_label.setText(
                f"Контент: {'Только видео' if self.media_filter == 'video_only' else 'Фото и видео'}"
            )

    def current_headless(self) -> bool:
        return self.download_mode == "background"

    def current_media_filter(self) -> str:
        return self.media_filter

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
        self.current_step_label = "Запускаю задачу."
        normalized_status = status_title.lower()
        if "скачив" in normalized_status or "выгруз" in normalized_status:
            self.begin_live_download_tracking()
        self.refresh_home2_status_strip()
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
        self.stop_live_download_tracking()
        self.refresh_live_download_tracking()
        self.refresh_batch_table()

    def cleanup_request(self) -> None:
        self.current_task = None
        self.refresh_batch_table()

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
            self.update_current_step_from_log(line)
            self.append_log(line)
        for item in reversed(response.items):
            list_item = QtWidgets.QListWidgetItem(f"{item.mediaType.upper()}  {item.localPath}")
            list_item.setData(QtCore.Qt.UserRole, item.localPath)
            self.downloads_list.insertItem(0, list_item)
        if response.ok and self._response_saved_count(response) > 0 and response.status == "download_complete":
            self.trigger_celebration()

    def set_status(self, title: str, detail: str) -> None:
        self.status_title_label.setText(title)
        self.status_detail_label.setText(detail)
        self.refresh_home2_status_strip()

    def append_log(self, message: str) -> None:
        line = f"{display_now()}  {message}"
        self.logs_text.appendPlainText(line)
        scrollbar = self.logs_text.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())
        if hasattr(self, "home2_logs_text"):
            self.home2_logs_text.appendPlainText(line)
            home2_scroll = self.home2_logs_text.verticalScrollBar()
            home2_scroll.setValue(home2_scroll.maximum())

    def refresh_home2_status_strip(self) -> None:
        if not hasattr(self, "home2_status_label"):
            return
        is_active = self.batch_running or (self.current_task is not None)
        if is_active and not self.status_pulse_timer.isActive():
            self.status_pulse_timer.start()
        if not is_active and self.status_pulse_timer.isActive():
            self.status_pulse_timer.stop()
            self.status_pulse_active = False
        live_dot = "🟢" if self.status_pulse_active else "🟩"
        self.home2_status_label.setText(f"{self.status_title_label.text()}\n{self.status_detail_label.text()}")
        self.home2_step_label.setText(f"{live_dot} {self.current_step_label}" if is_active else self.current_step_label)
        self.home2_result_label.setText(f"{self.saved_label.text()}\n{self.found_label.text()}")
        self.home2_live_label.setText(
            f"{self.live_downloaded_file_count} файлов\n{self.live_created_folder_count} папок создано"
        )
        if hasattr(self, "home2_last_result"):
            self.home2_last_result.setText(self.activity_subtitle.text())
        if hasattr(self, "home2_session_summary"):
            self.home2_session_summary.setText(self.session_summary)
        if hasattr(self, "home2_worker_summary"):
            self.home2_worker_summary.setText(self.worker_summary)
        if hasattr(self, "home2_queue_count"):
            self.home2_queue_count.setText(f"В очереди: {len(self.batch_entries)}")
        if hasattr(self, "home2_recent_count"):
            self.home2_recent_count.setText(f"Недавних наборов: {len(self.recent_lists)}")
        if hasattr(self, "home2_media_label"):
            self.home2_media_label.setText(
                f"Контент: {'Только видео' if self.media_filter == 'video_only' else 'Фото и видео'}"
            )

    def _tick_status_pulse(self) -> None:
        self.status_pulse_active = not self.status_pulse_active
        self.refresh_home2_status_strip()

    def update_current_step_from_log(self, message: str) -> None:
        lowered = message.lower()
        if "opened=" in lowered or "checked=" in lowered:
            self.current_step_label = "Открываю страницу Instagram."
        elif "storage_state_saved=" in lowered:
            self.current_step_label = "Сохраняю браузерную сессию."
        elif "saved=" in lowered:
            self.current_step_label = "Сохраняю файл на диск."
        elif "manifest=" in lowered:
            self.current_step_label = "Записываю метаданные загрузки."
        elif "playwright=" in lowered or "worker_runtime=" in lowered:
            self.current_step_label = "Проверяю runtime и зависимости."
        elif "batch_chunk_" in lowered:
            self.current_step_label = "Перехожу к следующей пачке профилей."
        self.refresh_home2_status_strip()

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

    def resizeEvent(self, event: QtGui.QResizeEvent) -> None:
        super().resizeEvent(event)
        if hasattr(self, "confetti_overlay"):
            self.confetti_overlay.setGeometry(self.centralWidget().rect())

    def begin_live_download_tracking(self) -> None:
        self.refresh_live_download_tracking()
        if not self.live_tracking_timer.isActive():
            self.live_tracking_timer.start()

    def stop_live_download_tracking(self) -> None:
        if self.live_tracking_timer.isActive():
            self.live_tracking_timer.stop()

    def reset_live_download_tracking_baseline(self) -> None:
        files, folders = self.snapshot_download_counts()
        self._save_directory_baseline_files = files
        self._save_directory_baseline_folders = folders
        self.live_downloaded_file_count = 0
        self.live_created_folder_count = 0

    def refresh_live_download_tracking(self) -> None:
        files, folders = self.snapshot_download_counts()
        self.live_downloaded_file_count = max(0, files - self._save_directory_baseline_files)
        self.live_created_folder_count = max(0, folders - self._save_directory_baseline_folders)
        self.refresh_home2_status_strip()

    def snapshot_download_counts(self) -> tuple[int, int]:
        root = self.save_directory
        if not root.exists():
            return (0, 0)
        file_count = 0
        folder_count = 0
        media_suffixes = {".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".m4v"}
        try:
            for current_root, directories, filenames in os.walk(root):
                folder_count += len(directories)
                file_count += sum(1 for name in filenames if Path(name).suffix.lower() in media_suffixes)
        except Exception:
            return (0, 0)
        return (file_count, folder_count)

    def _response_saved_count(self, response: WorkerResponse) -> int:
        raw = str(response.data.get("savedCount", "")).strip()
        if raw.isdigit():
            return int(raw)
        return len(response.items)

    def trigger_celebration(self) -> None:
        self.play_success_sound()
        if hasattr(self, "confetti_overlay"):
            self.confetti_overlay.launch()

    def play_success_sound(self) -> None:
        if winsound is not None:
            try:
                winsound.PlaySound("SystemAsterisk", winsound.SND_ALIAS | winsound.SND_ASYNC)
                return
            except Exception:
                pass
        QtWidgets.QApplication.beep()

    def closeEvent(self, event: QtGui.QCloseEvent) -> None:
        if self.login_poll_timer.isActive():
            self.login_poll_timer.stop()
        self.stop_live_download_tracking()
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
        spec = importlib.util.spec_from_file_location("savestories_worker_bridge", worker_path)
        if spec is None or spec.loader is None:
            raise SystemExit("Не удалось загрузить встроенный worker bridge.")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.main()
        raise SystemExit(0)

    raise SystemExit(main())



