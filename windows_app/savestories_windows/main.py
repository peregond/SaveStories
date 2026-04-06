from __future__ import annotations

import json
import os
import sys
import importlib.util
from pathlib import Path

from PySide6 import QtCore, QtGui, QtWidgets

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from savestories_windows.app_paths import AppPaths
    from savestories_windows.batch_flow import MainWindowBatchFlowMixin
    from savestories_windows.common_utils import (
        batch_status_title,
        normalize_profile_link,
        parse_batch_links,
        suggested_recent_list_title,
    )
    from savestories_windows.models import BatchEntry, WorkerRequest, WorkerResponse
    from savestories_windows.ui_layout import MainWindowLayoutMixin
    from savestories_windows.runtime_flow import MainWindowRuntimeFlowMixin
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
        install_global_exception_hooks,
        scaled,
        write_crash_log,
    )
    from savestories_windows.worker_client import WorkerClient
else:
    from .app_paths import AppPaths
    from .batch_flow import MainWindowBatchFlowMixin
    from .common_utils import (
        batch_status_title,
        normalize_profile_link,
        parse_batch_links,
        suggested_recent_list_title,
    )
    from .models import BatchEntry, WorkerRequest, WorkerResponse
    from .ui_layout import MainWindowLayoutMixin
    from .runtime_flow import MainWindowRuntimeFlowMixin
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
        install_global_exception_hooks,
        scaled,
        write_crash_log,
    )
    from .worker_client import WorkerClient


class MainWindow(
    MainWindowBatchFlowMixin,
    MainWindowUpdateFlowMixin,
    MainWindowRuntimeFlowMixin,
    MainWindowLayoutMixin,
    QtWidgets.QMainWindow,
):
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
        self.current_theme = str(self.settings_store.value("theme", "dark") or "dark").strip().lower()
        if self.current_theme not in {"dark", "light"}:
            self.current_theme = "dark"
        self.prevent_sleep_during_downloads = self._settings_bool("prevent_sleep_during_downloads", True)
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
        self.download_request_active = False
        self.sleep_prevention_active = False
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
        self.setMinimumSize(scaled(860), scaled(560))
        default_size = QtCore.QSize(scaled(1180), scaled(740))
        saved_geometry = self.settings_store.value("window_geometry")
        if isinstance(saved_geometry, QtCore.QByteArray) and not saved_geometry.isEmpty():
            self.restoreGeometry(saved_geometry)
        else:
            self.resize(default_size)
        self._build_ui()
        self.confetti_overlay = ConfettiOverlay(self.centralWidget())
        self.settings_dialog.theme_changed.connect(self.set_theme)
        self.settings_dialog.set_theme_value(self.current_theme)
        self._apply_styles()
        self.refresh_recent_lists_ui()
        self.refresh_home2_status_strip()
        self.refresh_ui_action_states()

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

    def open_settings(self) -> None:
        self.settings_dialog.update_state(
            worker_summary=self.worker_summary,
            session_summary=self.session_summary,
            runtime_summary=self.runtime_summary,
            update_summary=self.update_summary,
            prevent_sleep_during_downloads=self.prevent_sleep_during_downloads,
        )
        self.settings_dialog.set_theme_value(self.current_theme)
        self.stack.setCurrentIndex(3)
        if hasattr(self, "settings_nav_button"):
            self.settings_nav_button.setChecked(True)

    def set_theme(self, theme: str) -> None:
        normalized = "light" if str(theme).strip().lower() == "light" else "dark"
        if normalized == self.current_theme:
            self.settings_dialog.set_theme_value(self.current_theme)
            return
        self.current_theme = normalized
        self.settings_store.setValue("theme", self.current_theme)
        self._apply_styles()
        self.settings_dialog.set_theme_value(self.current_theme)

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

    def closeEvent(self, event: QtGui.QCloseEvent) -> None:
        if self.login_poll_timer.isActive():
            self.login_poll_timer.stop()
        self.end_sleep_prevention()
        self.stop_live_download_tracking()
        self.settings_store.setValue("window_geometry", self.saveGeometry())
        write_crash_log("MainWindow.closeEvent", "Window close requested.")
        super().closeEvent(event)

    def _settings_bool(self, key: str, default: bool) -> bool:
        value = self.settings_store.value(key, default)
        if isinstance(value, bool):
            return value
        return str(value).strip().lower() not in {"0", "false", "no", "off", ""}


def main() -> int:
    install_global_exception_hooks()
    os.environ["QT_SCALE_FACTOR_ROUNDING_POLICY"] = "PassThrough"
    QtWidgets.QApplication.setApplicationName("SaveStories")
    QtWidgets.QApplication.setApplicationVersion(app_version())
    QtWidgets.QApplication.setHighDpiScaleFactorRoundingPolicy(
        QtCore.Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )
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
