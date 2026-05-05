from __future__ import annotations

import os
import traceback
from datetime import datetime
from pathlib import Path
from typing import Callable

from PySide6 import QtCore, QtGui, QtWidgets

try:
    import winsound
except ImportError:
    winsound = None

from .app_paths import AppPaths
from .common_utils import normalize_profile_link, parse_reel_links, snapshot_download_counts
from .models import WorkerRequest, WorkerResponse
from .ui_support import (
    BootstrapTask,
    WorkerTask,
    prevent_system_sleep,
    restore_system_sleep,
    write_crash_log,
)


class MainWindowRuntimeFlowMixin:
    def prepare(self) -> None:
        try:
            write_crash_log("MainWindow.prepare", "Startup UI prepare started.")
            self.append_log(f"Подготовлены папки приложения в {AppPaths.application_support()}.")
            self.set_status("Готово", "Приложение запущено. Автоматические фоновые проверки отключены.")
            self.activity_subtitle.setText(
                "Приложение запущено. Проверки среды, сессии и обновлений доступны вручную в настройках."
            )
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
            prevent_sleep_during_downloads=self.prevent_sleep_during_downloads,
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
            f"logs={response.data.get('logsDirectory', str(AppPaths.logs_directory()))}",
            f"default_downloads={AppPaths.default_downloads()}",
            f"health={response.data.get('health', '[]')}",
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
            self.activity_subtitle.setText(
                "Выполни вход в Instagram в открытом окне браузера. Приложение само обнаружит сохранённую сессию."
            )
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
            prevent_sleep_during_downloads=self.prevent_sleep_during_downloads,
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

    def handle_download_response(self, response: WorkerResponse) -> None:
        self.apply_response(response)

    def download_reels(self) -> None:
        links = parse_reel_links(self.reels_input.toPlainText())
        if not links:
            self.append_log("Не найдено ни одной ссылки на Reels.")
            return

        self.start_request(
            WorkerRequest(
                command="download_reels_urls",
                url=None,
                urls=links,
                outputDirectory=str(self.save_directory),
                headless=self.current_headless(),
                mediaFilter=None,
            ),
            "Скачивание Reels",
            callback=self.handle_download_response,
        )
        self.reels_input.clear()

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
        if hasattr(self, "reels_directory_line"):
            self.reels_directory_line.setText(str(self.save_directory))
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
        is_download_request = self.should_prevent_sleep_for_request(request)
        if "скачив" in normalized_status or "выгруз" in normalized_status:
            self.begin_live_download_tracking()
        if is_download_request:
            self.download_request_active = True
            self.refresh_sleep_prevention_for_current_state()
        self.refresh_home2_status_strip()
        self.refresh_ui_action_states()
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
        finally:
            self.download_request_active = False
            self.refresh_sleep_prevention_for_current_state()
            self.stop_live_download_tracking()
            self.refresh_live_download_tracking()
            self.refresh_batch_table()
            self.refresh_ui_action_states()

    def cleanup_request(self) -> None:
        self.current_task = None
        self.download_request_active = False
        self.refresh_sleep_prevention_for_current_state()
        self.refresh_batch_table()
        self.refresh_ui_action_states()

    def apply_response(self, response: WorkerResponse) -> None:
        self.set_status("Готово" if response.ok else "Ошибка", response.message)
        if response.counts is not None:
            self.found_label.setText(f"Найдено: {response.counts.found}")
        elif "foundCount" in response.data:
            self.found_label.setText(f"Найдено: {response.data['foundCount']}")
        elif response.status.startswith("download"):
            self.found_label.setText(f"Найдено: {len(response.items)}")

        if response.counts is not None:
            self.saved_label.setText(f"Сохранено: {response.counts.saved}")
        elif "savedCount" in response.data:
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
            if hasattr(self, "reels_downloads_list"):
                reels_item = QtWidgets.QListWidgetItem(f"{item.mediaType.upper()}  {item.localPath}")
                reels_item.setData(QtCore.Qt.UserRole, item.localPath)
                self.reels_downloads_list.insertItem(0, reels_item)
        if response.ok and self._response_saved_count(response) > 0 and response.status == "download_complete":
            self.trigger_celebration()

    def set_status(self, title: str, detail: str) -> None:
        self.status_title_label.setText(title)
        self.status_detail_label.setText(detail)
        if hasattr(self, "reels_status_badge"):
            lowered = title.lower()
            if "ошибка" in lowered:
                tone = "error"
                badge = "Ошибка"
            elif "готов" in lowered:
                tone = "success"
                badge = "Готово"
            elif "скачив" in lowered or "выгруз" in lowered or self.current_task is not None:
                tone = "active"
                badge = "Загружаю"
            else:
                tone = "idle"
                badge = "Ожидание"
            self.reels_status_badge.setText(badge)
            self.reels_status_badge.setProperty("statusTone", tone)
            self.reels_status_badge.style().unpolish(self.reels_status_badge)
            self.reels_status_badge.style().polish(self.reels_status_badge)
            if hasattr(self, "reels_status_card_frame"):
                self.reels_status_card_frame.setProperty("statusTone", tone)
                self.reels_status_card_frame.style().unpolish(self.reels_status_card_frame)
                self.reels_status_card_frame.style().polish(self.reels_status_card_frame)
            self.reels_status_summary.setText(detail)
        self.refresh_home2_status_strip()

    def append_log(self, message: str) -> None:
        from .ui_support import display_now

        line = f"{display_now()}  {message}"
        self.logs_text.appendPlainText(line)
        scrollbar = self.logs_text.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())
        if hasattr(self, "home2_logs_text"):
            self.home2_logs_text.appendPlainText(line)
            home2_scroll = self.home2_logs_text.verticalScrollBar()
            home2_scroll.setValue(home2_scroll.maximum())
        if hasattr(self, "reels_logs_text"):
            self.reels_logs_text.appendPlainText(line)
            reels_scroll = self.reels_logs_text.verticalScrollBar()
            reels_scroll.setValue(reels_scroll.maximum())

    def refresh_home2_status_strip(self) -> None:
        is_active = self.batch_running or (self.current_task is not None)
        if is_active and not self.status_pulse_timer.isActive():
            self.status_pulse_timer.start()
        if not is_active and self.status_pulse_timer.isActive():
            self.status_pulse_timer.stop()
            self.status_pulse_active = False
        def extract_count(label_text: str) -> str:
            _, _, value = label_text.partition(":")
            return value.strip() or "0"

        if hasattr(self, "home2_status_badge"):
            title = self.status_title_label.text()
            if is_active:
                badge_text = "Загружаю"
                tone = "active"
            elif "ошибка" in title.lower():
                badge_text = "Ошибка"
                tone = "error"
            elif "готов" in title.lower():
                badge_text = "Готово"
                tone = "success"
            else:
                badge_text = "Ожидание"
                tone = "idle"

            self.home2_status_badge.setText(badge_text)
            self.home2_status_badge.setProperty("statusTone", tone)
            self.home2_status_badge.style().unpolish(self.home2_status_badge)
            self.home2_status_badge.style().polish(self.home2_status_badge)
            if hasattr(self, "home2_status_card_frame"):
                self.home2_status_card_frame.setProperty("statusTone", tone)
                self.home2_status_card_frame.style().unpolish(self.home2_status_card_frame)
                self.home2_status_card_frame.style().polish(self.home2_status_card_frame)
            self.home2_status_summary.setText(self.status_detail_label.text())
            live_prefix = "● " if is_active and self.status_pulse_active else ("○ " if is_active else "")
            self.home2_step_value.setText(f"{live_prefix}{self.current_step_label}")

        if hasattr(self, "home2_profiles_value"):
            self.home2_profiles_value.setText(extract_count(self.found_label.text()))
        if hasattr(self, "home2_saved_value"):
            self.home2_saved_value.setText(extract_count(self.saved_label.text()))
        if hasattr(self, "home2_files_value"):
            self.home2_files_value.setText(str(self.live_downloaded_file_count))
        if hasattr(self, "home2_folders_value"):
            self.home2_folders_value.setText(str(self.live_created_folder_count))

        if hasattr(self, "home2_progress_bar"):
            total = max(len(self.batch_pending_indices), len(self.batch_entries), 0)
            if self.batch_running and total > 0:
                completed = max(self.batch_cursor - 1, 0)
                self.home2_progress_bar.setMaximum(total)
                self.home2_progress_bar.setValue(min(completed, total))
                self.home2_progress_bar.setVisible(True)
            else:
                self.home2_progress_bar.setVisible(False)

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

    def refresh_ui_action_states(self) -> None:
        if hasattr(self, "reels_run_button"):
            busy = self.current_task is not None
            self.reels_run_button.setEnabled(bool(self.reels_input.toPlainText().strip()) and not busy)
            self.reels_clear_button.setEnabled(not busy)
            self.reels_run_button.setText("Загружаю..." if busy else "Скачать")

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

    def begin_live_download_tracking(self) -> None:
        self.refresh_live_download_tracking()
        if not self.live_tracking_timer.isActive():
            self.live_tracking_timer.start()

    def stop_live_download_tracking(self) -> None:
        if self.live_tracking_timer.isActive():
            self.live_tracking_timer.stop()

    def reset_live_download_tracking_baseline(self) -> None:
        files, folders = snapshot_download_counts(self.save_directory)
        self._save_directory_baseline_files = files
        self._save_directory_baseline_folders = folders
        self.live_downloaded_file_count = 0
        self.live_created_folder_count = 0

    def refresh_live_download_tracking(self) -> None:
        files, folders = snapshot_download_counts(self.save_directory)
        self.live_downloaded_file_count = max(0, files - self._save_directory_baseline_files)
        self.live_created_folder_count = max(0, folders - self._save_directory_baseline_folders)
        self.refresh_home2_status_strip()

    def snapshot_download_counts(self) -> tuple[int, int]:
        return snapshot_download_counts(self.save_directory)

    def _response_saved_count(self, response: WorkerResponse) -> int:
        raw = str(response.data.get("savedCount", "")).strip()
        if raw.isdigit():
            return int(raw)
        if response.counts is not None:
            return response.counts.saved
        return len(response.items)

    def trigger_celebration(self) -> None:
        self.play_success_sound()
        if hasattr(self, "confetti_overlay"):
            self.confetti_overlay.launch()

    def set_prevent_sleep_during_downloads(self, enabled: bool) -> None:
        self.prevent_sleep_during_downloads = bool(enabled)
        self.settings_store.setValue("prevent_sleep_during_downloads", self.prevent_sleep_during_downloads)
        self.refresh_sleep_prevention_for_current_state()

    def should_prevent_sleep_for_request(self, request: WorkerRequest) -> bool:
        return request.command in {"download_profile_stories", "download_profile_batch", "download_reels_urls"}

    def refresh_sleep_prevention_for_current_state(self) -> None:
        if self.prevent_sleep_during_downloads and self.download_request_active:
            self.begin_sleep_prevention()
        else:
            self.end_sleep_prevention()

    def begin_sleep_prevention(self) -> None:
        if self.sleep_prevention_active:
            return
        if prevent_system_sleep():
            self.sleep_prevention_active = True

    def end_sleep_prevention(self) -> None:
        if not self.sleep_prevention_active:
            return
        restore_system_sleep()
        self.sleep_prevention_active = False

    def play_success_sound(self) -> None:
        if winsound is not None:
            try:
                winsound.PlaySound("SystemAsterisk", winsound.SND_ALIAS | winsound.SND_ASYNC)
                return
            except Exception:
                pass
        QtWidgets.QApplication.beep()
