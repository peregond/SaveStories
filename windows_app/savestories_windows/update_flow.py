from __future__ import annotations

from datetime import datetime
import traceback

from PySide6 import QtCore, QtGui, QtWidgets

from .ui_support import UpdateCheckTask, UpdateInstallTask, app_version, write_crash_log
from .updater import ReleaseInfo


class MainWindowUpdateFlowMixin:
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
                prevent_sleep_during_downloads=self.prevent_sleep_during_downloads,
            )
            self.settings_dialog.set_update_action_available(False)
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
                prevent_sleep_during_downloads=self.prevent_sleep_during_downloads,
            )
            self.settings_dialog.set_update_action_available(False)
            return

        if status == "up_to_date":
            self.update_summary = f"Уже установлена актуальная версия {app_version()}."
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
                prevent_sleep_during_downloads=self.prevent_sleep_during_downloads,
            )
            self.settings_dialog.set_update_action_available(False)
            if not self.silent_update_check:
                self.set_status("Готово", "Новая версия не найдена.")
                self.append_log("Новая Windows-версия не найдена.")
            return

        if status == "update_available" and isinstance(release, ReleaseInfo):
            self.pending_release = release
            if self.updater.supports_auto_install:
                self.update_summary = (
                    f"Доступна версия {release.version}. "
                    "Можно скачать установщик и применить обновление поверх текущей сборки."
                )
            else:
                self.update_summary = (
                    f"Доступна версия {release.version}. "
                    "Автоустановка отключена для portable-сборки: скачай новый установщик вручную."
                )
            self.settings_dialog.update_state(
                worker_summary=self.worker_summary,
                session_summary=self.session_summary,
                runtime_summary=self.runtime_summary,
                update_summary=self.update_summary,
                prevent_sleep_during_downloads=self.prevent_sleep_during_downloads,
            )
            self.settings_dialog.set_update_action_available(False)
            self.append_log(f"Найдена новая версия Windows: {release.version}.")
            if self.silent_update_check:
                if self.updater.supports_auto_install:
                    self.append_log("Автопроверка: обновление найдено. Установка доступна вручную через приложение.")
                else:
                    self.append_log("Автопроверка: обновление найдено. Для portable-сборки нужен ручной запуск установщика.")
                return
            self.prompt_update_install(release)

    def prompt_update_install(self, release: ReleaseInfo) -> None:
        details = release.notes.strip() or "GitHub release опубликован без release notes."
        dialog = QtWidgets.QDialog(self)
        dialog.setWindowTitle("Доступно обновление")
        dialog.setModal(True)
        dialog.setMinimumWidth(520)

        layout = QtWidgets.QVBoxLayout(dialog)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        title = QtWidgets.QLabel(f"Доступна новая версия SaveMe {release.version}.")
        title.setStyleSheet("font-weight: 600;")
        title.setWordWrap(True)
        layout.addWidget(title)

        body = QtWidgets.QLabel()
        body.setWordWrap(True)
        if self.updater.supports_auto_install:
            body.setText(
                "Сейчас можно скачать установщик обновления и затем применить его через кнопку в настройках или в левом меню."
            )
            primary_label = "Скачать обновление"
        else:
            body.setText(
                "Текущая Windows-сборка работает в portable-режиме. Для обновления открой установщик новой версии."
            )
            primary_label = "Скачать установщик"
        layout.addWidget(body)

        details_toggle = QtWidgets.QToolButton()
        details_toggle.setText("Показать подробности")
        details_toggle.setCheckable(True)
        details_toggle.setChecked(False)
        details_toggle.setToolButtonStyle(QtCore.Qt.ToolButtonTextOnly)

        details_box = QtWidgets.QPlainTextEdit()
        details_box.setReadOnly(True)
        details_box.setPlainText(details)
        details_box.setVisible(False)
        details_box.setMinimumHeight(140)

        def toggle_details(checked: bool) -> None:
            details_box.setVisible(checked)
            details_toggle.setText("Скрыть подробности" if checked else "Показать подробности")
            dialog.adjustSize()

        details_toggle.toggled.connect(toggle_details)
        layout.addWidget(details_toggle, 0, QtCore.Qt.AlignLeft)
        layout.addWidget(details_box)

        buttons = QtWidgets.QHBoxLayout()
        buttons.setContentsMargins(0, 0, 0, 0)
        buttons.setSpacing(8)
        buttons.addStretch(1)

        later_button = QtWidgets.QPushButton("Позже")
        later_button.setProperty("secondary", True)
        later_button.clicked.connect(dialog.reject)

        install_button = QtWidgets.QPushButton(primary_label)
        install_button.setObjectName("accentButton")
        install_button.clicked.connect(dialog.accept)

        buttons.addWidget(later_button)
        buttons.addWidget(install_button)
        layout.addLayout(buttons)

        if dialog.exec() == QtWidgets.QDialog.Accepted:
            if self.updater.supports_auto_install:
                self.install_update(release, initiated_by_user=True)
            else:
                self.open_release_asset(release)

    def install_update(self, release: ReleaseInfo, *, initiated_by_user: bool = False) -> None:
        if not initiated_by_user:
            self.append_log("Запуск установки обновления без подтверждения пользователя заблокирован.")
            return

        if self.update_install_task is not None and self.update_install_task.isRunning():
            return

        if not self.updater.supports_auto_install:
            self.open_release_asset(release)
            return

        self.update_ready_to_apply = False
        self.apply_update_sidebar_button.setVisible(False)
        self.apply_update_sidebar_button.setEnabled(False)
        self.settings_dialog.set_update_action_available(False)
        self.set_status("Обновление", f"Скачиваю установщик SaveMe {release.version}.")
        self.append_log(f"Начинаю скачивание установщика обновления Windows: {release.version}.")
        self.update_download_progress = 0
        self.last_logged_update_progress = -1
        self.update_install_task = UpdateInstallTask(self.updater, release)
        self.update_install_task.progress_output.connect(self.handle_update_install_progress)
        self.update_install_task.finished_output.connect(self.handle_update_install_result)
        self.update_install_task.start()

    def handle_update_install_progress(self, percent: int, message: str) -> None:
        self.update_download_progress = percent
        self.set_status("Обновление", message)
        if percent in {0, 100} or percent >= self.last_logged_update_progress + 10:
            self.last_logged_update_progress = percent
            self.append_log(message)

    def handle_update_install_result(self, ok: bool, message: str) -> None:
        self.update_install_task = None
        if not ok:
            self.set_status("Ошибка", message)
            self.append_log(f"[update_install_error] {message}")
            return

        self.update_ready_to_apply = True
        self.apply_update_sidebar_button.setVisible(True)
        self.apply_update_sidebar_button.setEnabled(True)
        self.settings_dialog.set_update_action_available(True)
        self.set_status("Обновление", message)
        self.append_log(message)
        self.append_log("Кнопка «Установить обновление» доступна и в настройках, и в левом меню.")
        self.append_log("После нажатия кнопки откроется установщик Windows с запросом прав администратора.")

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

        self.set_status("Обновление", "Запускаю установщик обновления...")
        self.append_log(f"Запуск установки обновления. Лог: {log_path}")
        self.append_log("Если Windows покажет запрос контроля учётных записей, подтверди его. После этого приложение закроется и начнётся обновление.")
        QtCore.QTimer.singleShot(700, QtWidgets.QApplication.instance().quit)

    def open_release_asset(self, release: ReleaseInfo) -> None:
        url = release.asset.url or release.html_url
        if not url:
            self.append_log("У обновления нет ссылки для скачивания.")
            return
        opened = QtGui.QDesktopServices.openUrl(QtCore.QUrl(url))
        if opened:
            self.append_log(f"Открыл ссылку на установщик обновления: {url}")
            self.set_status("Обновление", "Открыл ссылку на установщик новой версии.")
        else:
            self.append_log(f"Не удалось открыть ссылку на обновление: {url}")
            self.set_status("Ошибка", "Не удалось открыть страницу скачивания обновления.")
