from __future__ import annotations

from PySide6 import QtCore, QtGui, QtWidgets

from .common_utils import parse_batch_links
from .ui_support import SettingsDialog, app_version, scaled


class MainWindowLayoutMixin:
    def _scale_size(self, width: int, height: int) -> QtCore.QSize:
        return QtCore.QSize(scaled(width), scaled(height))

    def _nav_subtitle(self, text: str, limit: int = 26) -> str:
        compact = " ".join(text.split())
        if len(compact) <= limit:
            return compact
        return compact[: max(1, limit - 1)].rstrip() + "…"

    def _theme_palette(self) -> dict[str, str]:
        if getattr(self, "current_theme", "dark") == "light":
            return {
                "window_bg": "#f3f3f3",
                "card_bg": "#ffffff",
                "card_border": "#e0e0e0",
                "primary_text": "#1a1a1a",
                "secondary_text": "#666666",
                "input_bg": "#fafafa",
                "input_border": "#d0d0d0",
                "accent": "#0067c0",
                "button_bg": "#f0f0f0",
                "button_hover": "#e5e5e5",
                "button_disabled": "#f5f5f5",
                "section_header": "#888888",
                "nav_bg": "#ebebeb",
                "nav_hover": "#e0e0e0",
                "nav_selected": "#ffffff",
                "nav_border": "rgba(0,0,0,0.08)",
                "card_overlay": "rgba(255,255,255,0.92)",
                "subcard_bg": "#f7f7f7",
                "badge_bg": "#f1f1f1",
                "idle_bg": "#666666",
                "idle_fg": "#ffffff",
                "success_bg": "#107c10",
                "success_fg": "#ffffff",
                "error_bg": "#c42b1c",
                "error_fg": "#ffffff",
                "active_bg": "#0067c0",
                "active_fg": "#ffffff",
                "danger_bg": "rgba(196, 43, 28, 0.12)",
                "danger_border": "rgba(196, 43, 28, 0.45)",
                "danger_text": "#c42b1c",
                "scroll_handle": "rgba(0,0,0,0.22)",
            }
        return {
            "window_bg": "#1a1a1a",
            "card_bg": "#2a2a2a",
            "card_border": "#3a3a3a",
            "primary_text": "#f0f0f0",
            "secondary_text": "#888888",
            "input_bg": "#222222",
            "input_border": "#3a3a3a",
            "accent": "#3b7dd8",
            "button_bg": "#333333",
            "button_hover": "#404040",
            "button_disabled": "#262626",
            "section_header": "#666666",
            "nav_bg": "#141414",
            "nav_hover": "#222222",
            "nav_selected": "#2a2a2a",
            "nav_border": "rgba(255,255,255,0.08)",
            "card_overlay": "rgba(42,42,42,0.88)",
            "subcard_bg": "rgba(255,255,255,0.04)",
            "badge_bg": "rgba(255,255,255,0.08)",
            "idle_bg": "#666666",
            "idle_fg": "#ffffff",
            "success_bg": "#107c10",
            "success_fg": "#ffffff",
            "error_bg": "#c42b1c",
            "error_fg": "#ffffff",
            "active_bg": "#3b7dd8",
            "active_fg": "#ffffff",
            "danger_bg": "rgba(196, 43, 28, 0.15)",
            "danger_border": "rgba(196, 43, 28, 0.5)",
            "danger_text": "#ff6b6b",
            "scroll_handle": "rgba(255,255,255,0.18)",
        }

    def _theme_stylesheet(self) -> str:
        p = self._theme_palette()
        nav_h = scaled(52)
        btn_h = scaled(30)
        pad_x = scaled(12)
        small_pad_x = scaled(10)
        card_pad = scaled(12)
        radius_card = scaled(8)
        radius_button = scaled(4)
        radius_pill = scaled(12)
        stat_w = scaled(80)
        stat_h = scaled(64)
        status_h = scaled(26)
        status_w = scaled(90)
        input_min = scaled(140)
        sb_width = scaled(12)
        sb_handle = scaled(28)
        inline_radius = scaled(9)
        metric_value = scaled(24)
        icon_badge = scaled(10)
        clear_margin = scaled(8)
        progress_h = scaled(8)
        recent_remove_pad_h = scaled(2)
        recent_remove_pad_w = scaled(4)
        return f"""
            QMainWindow, QWidget#appRoot, QWidget#contentHost, QScrollArea, QScrollArea > QWidget > QWidget {{
                background: {p["window_bg"]};
                color: {p["primary_text"]};
                font-family: "Segoe UI Variable";
                font-size: {scaled(13)}px;
            }}
            QFrame#sidebar {{
                background: {p["nav_bg"]};
                border-right: 1px solid {p["nav_border"]};
            }}
            QFrame#navBrand {{
                background: {p["card_overlay"]};
                border: 1px solid {p["card_border"]};
                border-radius: {radius_card}px;
            }}
            QLabel#sidebarTitle {{
                font-size: {scaled(13)}px;
                font-weight: 600;
                color: {p["primary_text"]};
            }}
            QLabel#sidebarSubtitle {{
                font-size: {scaled(11)}px;
                color: {p["secondary_text"]};
            }}
            QLabel#sidebarVersion, QLabel#heroVersion, QLabel#valuePill {{
                font-size: {scaled(11)}px;
                color: {p["secondary_text"]};
                background: {p["badge_bg"]};
                border: 1px solid {p["card_border"]};
                border-radius: {radius_pill}px;
                padding: {scaled(3)}px {scaled(8)}px;
            }}
            QFrame#sidebarSeparator {{
                min-height: 1px;
                max-height: 1px;
                border: none;
                background: {p["nav_border"]};
                margin: {scaled(4)}px {scaled(2)}px;
            }}
            QPushButton[nav="true"] {{
                text-align: left;
                padding: {scaled(8)}px {pad_x}px {scaled(8)}px {pad_x}px;
                border-radius: {radius_card}px;
                border: 1px solid transparent;
                border-left: {scaled(3)}px solid transparent;
                background: transparent;
                color: {p["primary_text"]};
                font-size: {scaled(13)}px;
                font-weight: 500;
                min-height: {nav_h}px;
            }}
            QPushButton[nav="true"]:hover {{
                background: {p["nav_hover"]};
                border-color: {p["nav_border"]};
            }}
            QPushButton[nav="true"]:checked {{
                background: transparent;
                border-color: transparent;
                border-left: {scaled(3)}px solid {p["accent"]};
                color: {p["primary_text"]};
            }}
            QPushButton#applyUpdateButton, QPushButton#accentButton, QPushButton#queueActionButton {{
                background: {p["accent"]};
                color: white;
                border: 1px solid {p["accent"]};
                border-radius: {radius_button}px;
                padding: {scaled(6)}px {pad_x}px;
                min-height: {btn_h}px;
                font-size: {scaled(13)}px;
                font-weight: 600;
            }}
            QPushButton#applyUpdateButton:hover, QPushButton#accentButton:hover, QPushButton#queueActionButton:hover {{
                background: {p["accent"]};
                border-color: {p["accent"]};
            }}
            QPushButton#applyUpdateButton:disabled, QPushButton#accentButton:disabled, QPushButton#queueActionButton:disabled {{
                background: {p["button_disabled"]};
                color: {p["secondary_text"]};
                border-color: {p["card_border"]};
            }}
            QPushButton {{
                background: {p["button_bg"]};
                color: {p["primary_text"]};
                border: 1px solid {p["card_border"]};
                border-radius: {radius_button}px;
                padding: {scaled(6)}px {pad_x}px;
                min-height: {btn_h}px;
                font-size: {scaled(13)}px;
            }}
            QPushButton:hover {{
                background: {p["button_hover"]};
                border-color: {p["input_border"]};
            }}
            QPushButton:disabled {{
                background: {p["button_disabled"]};
                color: {p["secondary_text"]};
                border-color: {p["card_border"]};
            }}
            QPushButton[secondary="true"] {{
                background: transparent;
                color: {p["secondary_text"]};
                border: 1px solid {p["card_border"]};
            }}
            QPushButton[secondary="true"]:hover {{
                background: {p["button_hover"]};
                color: {p["primary_text"]};
            }}
            QPushButton[secondary="true"]:checked, QPushButton[segmented="true"]:checked {{
                background: {p["accent"]};
                color: white;
                border-color: {p["accent"]};
            }}
            QPushButton#prominentSecondaryButton {{
                border: 1px solid {p["accent"]};
                color: {p["primary_text"]};
            }}
            QPushButton#prominentSecondaryButton:hover {{
                background: {p["button_hover"]};
            }}
            QPushButton#subtleDangerButton:enabled {{
                background: {p["danger_bg"]};
                border: 1px solid {p["danger_border"]};
                color: {p["danger_text"]};
            }}
            QPushButton#subtleDangerButton:enabled:hover {{
                background: {p["danger_bg"]};
                border-color: {p["danger_border"]};
                color: {p["danger_text"]};
            }}
            QFrame#cardSurface, QFrame#subCard, QFrame#stepCard, QFrame#settingsCard, QFrame#settingsHero {{
                background: {p["card_overlay"]};
                border: 1px solid {p["card_border"]};
                border-radius: {radius_card}px;
            }}
            QFrame#statusCard[statusTone="active"] {{
                background: {p["card_overlay"]};
                border: 1px solid {p["card_border"]};
                border-left: {scaled(4)}px solid {p["active_bg"]};
                border-radius: {radius_card}px;
            }}
            QFrame#statusCard[statusTone="success"] {{
                background: {p["card_overlay"]};
                border: 1px solid {p["card_border"]};
                border-left: {scaled(4)}px solid {p["success_bg"]};
                border-radius: {radius_card}px;
            }}
            QFrame#statusCard[statusTone="error"] {{
                background: {p["card_overlay"]};
                border: 1px solid {p["card_border"]};
                border-left: {scaled(4)}px solid {p["error_bg"]};
                border-radius: {radius_card}px;
            }}
            QFrame#statusCard[statusTone="idle"] {{
                background: {p["card_overlay"]};
                border: 1px solid {p["card_border"]};
                border-left: {scaled(4)}px solid {p["idle_bg"]};
                border-radius: {radius_card}px;
            }}
            QFrame#inputShell, QFrame#segmentedGroup {{
                background: transparent;
                border: 1px solid {p["card_border"]};
                border-radius: {radius_button}px;
            }}
            QLabel#heroTitle {{
                font-size: {scaled(20)}px;
                font-weight: 600;
                color: {p["primary_text"]};
            }}
            QLabel#heroSubtitle, QLabel#dialogSubtitle, QLabel#mutedBody {{
                font-size: {scaled(13)}px;
                color: {p["secondary_text"]};
            }}
            QLabel#heroMiniTitle, QLabel#recentListTitle {{
                font-size: {scaled(13)}px;
                font-weight: 600;
                color: {p["primary_text"]};
            }}
            QLabel#sectionLabel {{
                font-size: {scaled(10)}px;
                font-weight: 600;
                color: {p["section_header"]};
                text-transform: uppercase;
                letter-spacing: 0.08em;
            }}
            QLabel#cardHint, QLabel#footnoteLabel, QLabel#inputCounter, QLabel#metricTitle {{
                font-size: {scaled(11)}px;
                color: {p["secondary_text"]};
            }}
            QLabel#statusBadge {{
                min-width: {status_w}px;
                min-height: {status_h}px;
                padding: {scaled(4)}px {small_pad_x}px;
                border-radius: {radius_pill}px;
                font-size: {scaled(11)}px;
                font-weight: 600;
                color: {p["idle_fg"]};
                background: {p["idle_bg"]};
                border: 1px solid {p["idle_bg"]};
            }}
            QLabel#statusBadge[statusTone="success"] {{ background: {p["success_bg"]}; border-color: {p["success_bg"]}; color: {p["success_fg"]}; }}
            QLabel#statusBadge[statusTone="error"] {{ background: {p["error_bg"]}; border-color: {p["error_bg"]}; color: {p["error_fg"]}; }}
            QLabel#statusBadge[statusTone="active"] {{ background: {p["active_bg"]}; border-color: {p["active_bg"]}; color: {p["active_fg"]}; }}
            QLabel#statusBadge[statusTone="idle"] {{ background: {p["idle_bg"]}; border-color: {p["idle_bg"]}; color: {p["idle_fg"]}; }}
            QLabel[badge="true"] {{
                background: {p["badge_bg"]};
                border: 1px solid {p["card_border"]};
                border-radius: {radius_pill}px;
                padding: {scaled(4)}px {small_pad_x}px;
                font-size: {scaled(11)}px;
                color: {p["secondary_text"]};
            }}
            QLineEdit, QPlainTextEdit, QListWidget, QTableWidget, QComboBox {{
                background: {p["input_bg"]};
                border: 1px solid {p["input_border"]};
                border-radius: {radius_button}px;
                padding: {scaled(8)}px;
                color: {p["primary_text"]};
                selection-background-color: {p["accent"]};
            }}
            QPlainTextEdit#profileEditor, QPlainTextEdit#logsText, QLabel#recentListPreview {{
                font-family: "Cascadia Mono";
                font-size: {scaled(13)}px;
            }}
            QLineEdit#pathField {{
                font-family: "Cascadia Mono";
                min-height: {btn_h}px;
            }}
            QPlainTextEdit#profileEditor {{
                min-height: {input_min}px;
            }}
            QListWidget::item {{
                padding: {scaled(8)}px;
                border-radius: {radius_button}px;
            }}
            QListWidget::item:hover {{
                background: {p["button_hover"]};
            }}
            QListWidget::item:selected {{
                background: {p["nav_selected"]};
            }}
            QTableWidget {{
                alternate-background-color: {p["subcard_bg"]};
                gridline-color: {p["card_border"]};
            }}
            QTableWidget::item {{
                padding: {scaled(6)}px;
            }}
            QHeaderView::section, QTableCornerButton::section {{
                background: {p["subcard_bg"]};
                border: none;
                border-bottom: 1px solid {p["card_border"]};
                padding: {scaled(8)}px;
                font-weight: 600;
                color: {p["primary_text"]};
            }}
            QToolButton#inlineClearButton {{
                background: {p["button_bg"]};
                border: 1px solid {p["card_border"]};
                border-radius: {icon_badge}px;
                padding: {scaled(2)}px;
                margin: {clear_margin}px;
            }}
            QToolButton#inlineClearButton:hover, QToolButton#inlineRemoveButton:hover {{
                background: {p["button_hover"]};
            }}
            QToolButton#inlineRemoveButton {{
                color: {p["secondary_text"]};
                background: {p["button_bg"]};
                border: 1px solid {p["card_border"]};
                border-radius: {inline_radius}px;
                padding: {recent_remove_pad_h}px {recent_remove_pad_w}px;
            }}
            QFrame#metricTile {{
                background: {p["subcard_bg"]};
                border: 1px solid {p["card_border"]};
                border-radius: {radius_card}px;
                min-width: {stat_w}px;
                min-height: {stat_h}px;
            }}
            QLabel#metricValue {{
                font-size: {metric_value}px;
                font-weight: 600;
                color: {p["primary_text"]};
            }}
            QLabel#metricDot {{
                font-size: {scaled(12)}px;
            }}
            QProgressBar#queueProgressBar {{
                background: {p["input_bg"]};
                border: 1px solid {p["input_border"]};
                border-radius: {radius_button}px;
                min-height: {progress_h}px;
                max-height: {progress_h}px;
            }}
            QProgressBar#queueProgressBar::chunk {{
                border-radius: {radius_button}px;
                background: {p["accent"]};
            }}
            QScrollBar:vertical {{
                background: transparent;
                width: {sb_width}px;
                margin: {scaled(2)}px 0;
            }}
            QScrollBar::handle:vertical {{
                background: {p["scroll_handle"]};
                min-height: {sb_handle}px;
                border-radius: {scaled(6)}px;
            }}
            QScrollBar::handle:vertical:hover {{
                background: {p["secondary_text"]};
            }}
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical,
            QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical,
            QScrollBar:horizontal, QScrollBar::handle:horizontal,
            QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal,
            QScrollBar::add-page:horizontal, QScrollBar::sub-page:horizontal {{
                background: transparent;
                border: none;
                width: 0px;
                height: 0px;
            }}
        """

    def _build_ui(self) -> None:
        central = QtWidgets.QWidget()
        central.setObjectName("appRoot")
        self.setCentralWidget(central)

        root = QtWidgets.QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        root.addWidget(self._build_sidebar())

        content_host = QtWidgets.QWidget()
        content_host.setObjectName("contentHost")
        content_layout = QtWidgets.QHBoxLayout(content_host)
        content_layout.setContentsMargins(scaled(24), scaled(20), scaled(24), scaled(20))
        content_layout.setSpacing(scaled(20))
        root.addWidget(content_host, 1)

        self.stack = QtWidgets.QStackedWidget()
        self.stack.addWidget(self._wrap_scroll_area(self._build_home_two_page()))
        self.stack.addWidget(self._wrap_scroll_area(self._build_batch_page()))
        self.stack.addWidget(self._wrap_scroll_area(self._build_reels_page()))
        self.settings_dialog = SettingsDialog(self)
        self.stack.addWidget(self._wrap_scroll_area(self.settings_dialog))
        self.stack.currentChanged.connect(self._sync_navigation_state)
        content_layout.addWidget(self.stack, 1)

        self.settings_dialog.refresh_requested.connect(self.refresh_environment)
        self.settings_dialog.bootstrap_requested.connect(self.bootstrap_environment)
        self.settings_dialog.login_requested.connect(self.login)
        self.settings_dialog.session_check_requested.connect(self.check_session)
        self.settings_dialog.update_check_requested.connect(lambda: self.check_for_updates(silent=False))
        self.settings_dialog.apply_update_requested.connect(self.apply_prepared_update)
        self.settings_dialog.open_runtime_requested.connect(self.open_runtime_directory)
        self.settings_dialog.prevent_sleep_toggled.connect(self.set_prevent_sleep_during_downloads)

    def _build_sidebar(self) -> QtWidgets.QWidget:
        sidebar = QtWidgets.QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(scaled(180))

        layout = QtWidgets.QVBoxLayout(sidebar)
        layout.setContentsMargins(scaled(10), scaled(14), scaled(10), scaled(10))
        layout.setSpacing(scaled(8))

        brand = QtWidgets.QFrame()
        brand.setObjectName("navBrand")
        brand_layout = QtWidgets.QVBoxLayout(brand)
        brand_layout.setContentsMargins(scaled(10), scaled(10), scaled(10), scaled(10))
        brand_layout.setSpacing(scaled(2))

        title = QtWidgets.QLabel("SaveMe")
        title.setObjectName("sidebarTitle")
        subtitle = QtWidgets.QLabel("Windows shell")
        subtitle.setObjectName("sidebarSubtitle")
        version_badge = QtWidgets.QLabel(app_version())
        version_badge.setObjectName("sidebarVersion")
        brand_layout.addWidget(title)
        brand_layout.addWidget(subtitle)
        brand_layout.addWidget(version_badge, 0, QtCore.Qt.AlignLeft)
        layout.addWidget(brand)

        self.nav_group = QtWidgets.QButtonGroup(self)
        self.nav_group.setExclusive(True)

        nav_specs = [
            ("◈", "Stories", "Скачать сторис из Instagram"),
            ("≡", "Очередь профилей", "Пакетная выгрузка и управление списком"),
            ("▶", "Reels", "Скачать Reels по ссылке"),
        ]
        for index, (symbol, text, detail) in enumerate(
            [
                *nav_specs,
            ]
        ):
            button = self._build_nav_button(symbol, text, detail)
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
        self.apply_update_sidebar_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_BrowserReload))
        self.apply_update_sidebar_button.clicked.connect(self.apply_prepared_update)
        layout.addWidget(self.apply_update_sidebar_button)

        footer_separator = QtWidgets.QFrame()
        footer_separator.setObjectName("sidebarSeparator")
        footer_separator.setFrameShape(QtWidgets.QFrame.HLine)
        layout.addWidget(footer_separator)

        self.settings_nav_button = self._build_nav_button(
            "⚙",
            "Настройки",
            "Обновления, среда и подключение к Instagram",
        )
        self.settings_nav_button.clicked.connect(self.open_settings)
        self.nav_group.addButton(self.settings_nav_button, 3)
        layout.addWidget(self.settings_nav_button)

        return sidebar

    def _wrap_scroll_area(self, widget: QtWidgets.QWidget) -> QtWidgets.QScrollArea:
        area = QtWidgets.QScrollArea()
        area.setObjectName("pageScrollArea")
        area.setWidgetResizable(True)
        area.setFrameShape(QtWidgets.QFrame.NoFrame)
        area.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        area.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAsNeeded)
        area.setWidget(widget)
        return area

    def _build_home_page(self) -> QtWidgets.QWidget:
        page = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(18)

        layout.addWidget(self._hero("SaveMe", "Windows-клиент для выгрузки активных stories из Instagram по ссылке на профиль."))
        layout.addWidget(self._status_card())
        layout.addWidget(self._save_directory_card())
        layout.addWidget(self._profile_card())
        layout.addStretch(1)
        return page

    def _build_reels_page(self) -> QtWidgets.QWidget:
        page = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(scaled(12))

        layout.addWidget(
            self._hero(
                "Reels",
                "Скачать Reels по ссылке",
                supporting="Выгрузка Reels тут",
            )
        )

        content_row = QtWidgets.QHBoxLayout()
        content_row.setSpacing(scaled(12))

        left_column = QtWidgets.QVBoxLayout()
        left_column.setSpacing(scaled(12))

        input_card = self._card("Ссылки на Reels")
        input_layout = QtWidgets.QVBoxLayout(input_card)
        input_layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        input_layout.setSpacing(scaled(12))
        input_layout.addWidget(self._section_caption("Ссылки на Reels"))

        note = QtWidgets.QLabel("Вставь одну или несколько ссылок. Каждая ссылка обработается отдельно.")
        note.setWordWrap(True)
        note.setObjectName("cardHint")
        input_layout.addWidget(note)

        input_shell = QtWidgets.QFrame()
        input_layout_shell = QtWidgets.QGridLayout(input_shell)
        input_layout_shell.setContentsMargins(0, 0, 0, 0)
        input_layout_shell.setSpacing(0)
        self.reels_input = QtWidgets.QPlainTextEdit()
        self.reels_input.setObjectName("profileEditor")
        self.reels_input.setPlaceholderText(
            "Например:\nhttps://www.instagram.com/reel/DMabc123/\nhttps://www.instagram.com/reel/DMxyz456/"
        )
        self.reels_input.setMinimumHeight(scaled(140))
        input_layout_shell.addWidget(self.reels_input, 0, 0)

        self.reels_clear_input_button = QtWidgets.QToolButton(input_shell)
        self.reels_clear_input_button.setObjectName("inlineClearButton")
        self.reels_clear_input_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_DialogCloseButton))
        self.reels_clear_input_button.setAutoRaise(True)
        self.reels_clear_input_button.clicked.connect(self.reels_input.clear)
        self.reels_clear_input_button.hide()
        input_layout_shell.addWidget(self.reels_clear_input_button, 0, 0, QtCore.Qt.AlignTop | QtCore.Qt.AlignRight)

        self.reels_input_counter = QtWidgets.QLabel("0 ссылок", input_shell)
        self.reels_input_counter.setObjectName("inputCounter")
        input_layout_shell.addWidget(self.reels_input_counter, 0, 0, QtCore.Qt.AlignBottom | QtCore.Qt.AlignRight)
        self.reels_input.textChanged.connect(self._update_reels_input_overlay)
        self.reels_input.textChanged.connect(lambda: hasattr(self, "refresh_ui_action_states") and self.refresh_ui_action_states())
        input_layout.addWidget(input_shell)

        buttons = QtWidgets.QHBoxLayout()
        buttons.setSpacing(scaled(8))
        self.reels_run_button = QtWidgets.QPushButton("Скачать")
        self.reels_run_button.setObjectName("queueActionButton")
        self.reels_run_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_ArrowDown))
        self.reels_run_button.clicked.connect(self.download_reels)
        clear_button = QtWidgets.QPushButton("Очистить")
        clear_button.setProperty("secondary", True)
        clear_button.clicked.connect(self.reels_input.clear)
        self.reels_clear_button = clear_button
        buttons.addWidget(self.reels_run_button, 1)
        buttons.addWidget(clear_button, 1)
        input_layout.addLayout(buttons)

        tip = QtWidgets.QLabel("Reels скачиваются отдельным потоком.")
        tip.setWordWrap(True)
        tip.setObjectName("footnoteLabel")
        input_layout.addWidget(tip)
        left_column.addWidget(input_card)
        left_column.addWidget(self._save_directory_card(reels_mode=True))
        left_column.addStretch(1)

        right_column = QtWidgets.QVBoxLayout()
        right_column.setSpacing(scaled(12))
        right_column.addWidget(self._reels_status_card())
        right_column.addWidget(self._reels_downloads_card())
        right_column.addWidget(self._reels_logs_card(), 1)

        left_host = QtWidgets.QWidget()
        left_host.setLayout(left_column)
        right_host = QtWidgets.QWidget()
        right_host.setLayout(right_column)
        right_host.setMinimumWidth(scaled(320))
        right_host.setMaximumWidth(scaled(400))

        content_row.addWidget(left_host, 3)
        content_row.addWidget(right_host, 2)
        layout.addLayout(content_row, 1)
        self._update_reels_input_overlay()
        if hasattr(self, "refresh_ui_action_states"):
            self.refresh_ui_action_states()
        return page

    def _build_home_two_page(self) -> QtWidgets.QWidget:
        page = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(scaled(12))

        layout.addWidget(
            self._hero(
                "Stories",
                "Скачать сторис из Instagram",
            )
        )

        content_row = QtWidgets.QHBoxLayout()
        content_row.setSpacing(scaled(12))

        left_column = QtWidgets.QVBoxLayout()
        left_column.setSpacing(scaled(12))
        left_column.addWidget(self._home2_composer_card())
        left_column.addWidget(self._home2_queue_card(), 1)

        right_column = QtWidgets.QVBoxLayout()
        right_column.setSpacing(scaled(12))
        right_column.addWidget(self._home2_status_card())
        right_column.addWidget(self._home2_result_card())
        right_column.addWidget(self._home2_recent_lists_card())
        right_column.addWidget(self._home2_activity_card(), 1)
        right_column.addStretch(1)

        left_host = QtWidgets.QWidget()
        left_host.setLayout(left_column)
        right_host = QtWidgets.QWidget()
        right_host.setLayout(right_column)
        right_host.setMinimumWidth(scaled(340))
        right_host.setMaximumWidth(scaled(420))

        content_row.addWidget(left_host, 3)
        content_row.addWidget(right_host, 2)
        layout.addLayout(content_row, 1)
        return page

    def _build_batch_page(self) -> QtWidgets.QWidget:
        page = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(scaled(12))

        layout.addWidget(
            self._hero(
                "Очередь профилей",
                "Добавь сразу несколько ссылок или usernames. Приложение обработает профили по очереди.",
                supporting="Управление списком профилей и массовой выгрузкой.",
            )
        )

        content_row = QtWidgets.QHBoxLayout()
        content_row.setSpacing(scaled(12))

        left_column = QtWidgets.QVBoxLayout()
        left_column.setSpacing(scaled(12))

        input_card = self._card("Добавить профили")
        input_layout = QtWidgets.QVBoxLayout(input_card)
        input_layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        input_layout.setSpacing(scaled(12))
        input_layout.addWidget(self._section_caption("Добавить профили"))
        self.batch_input = QtWidgets.QPlainTextEdit()
        self.batch_input.setObjectName("profileEditor")
        self.batch_input.setPlaceholderText("Вставь по одной ссылке или username на строку.\nНапример:\nhttps://www.instagram.com/dian.vegas1/\nmonetentony")
        self.batch_input.setMinimumHeight(scaled(140))
        input_layout.addWidget(self.batch_input)

        input_buttons = QtWidgets.QHBoxLayout()
        input_buttons.setSpacing(scaled(8))
        add_button = QtWidgets.QPushButton("Добавить в очередь")
        add_button.setProperty("secondary", True)
        add_button.clicked.connect(self.add_batch_profiles)
        clear_input = QtWidgets.QPushButton("Очистить")
        clear_input.setProperty("secondary", True)
        clear_input.clicked.connect(self.batch_input.clear)
        input_buttons.addWidget(add_button, 1)
        input_buttons.addWidget(clear_input, 1)
        input_layout.addLayout(input_buttons)
        left_column.addWidget(input_card)
        left_column.addWidget(self._save_directory_card(batch_mode=True))
        left_column.addWidget(self._mode_card(batch_mode=True))
        left_column.addStretch(1)

        queue_card = self._card("Очередь профилей")
        queue_layout = QtWidgets.QVBoxLayout(queue_card)
        queue_layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        queue_layout.setSpacing(scaled(12))
        queue_layout.addWidget(self._section_caption("Очередь профилей"))
        self.batch_progress_label = QtWidgets.QLabel("Очередь пока пуста.")
        self.batch_progress_label.setWordWrap(True)
        self.batch_progress_label.setObjectName("cardHint")
        queue_layout.addWidget(self.batch_progress_label)

        self.batch_table = QtWidgets.QTableWidget(0, 3)
        self.batch_table.setObjectName("queueTable")
        self.batch_table.setHorizontalHeaderLabels(["Профиль", "Статус", "Сообщение"])
        self.batch_table.horizontalHeader().setStretchLastSection(True)
        self.batch_table.horizontalHeader().setSectionResizeMode(0, QtWidgets.QHeaderView.Stretch)
        self.batch_table.horizontalHeader().setSectionResizeMode(1, QtWidgets.QHeaderView.ResizeToContents)
        self.batch_table.verticalHeader().setVisible(False)
        self.batch_table.verticalHeader().setDefaultSectionSize(scaled(28))
        self.batch_table.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.batch_table.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.batch_table.setAlternatingRowColors(True)
        self.batch_table.setMinimumHeight(220)
        queue_layout.addWidget(self.batch_table)

        queue_buttons = QtWidgets.QHBoxLayout()
        queue_buttons.setSpacing(scaled(8))
        self.batch_run_button = QtWidgets.QPushButton("Скачать очередь")
        self.batch_run_button.setObjectName("queueActionButton")
        self.batch_run_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_ArrowDown))
        self.batch_run_button.clicked.connect(self.start_batch)
        self.batch_stop_button = QtWidgets.QPushButton("Остановить")
        self.batch_stop_button.setObjectName("subtleDangerButton")
        self.batch_stop_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_BrowserStop))
        self.batch_stop_button.clicked.connect(self.stop_batch)
        self.batch_stop_button.setEnabled(False)
        clear_button = QtWidgets.QPushButton("Очистить очередь")
        clear_button.setProperty("secondary", True)
        clear_button.clicked.connect(self.clear_batch)
        queue_buttons.addWidget(self.batch_run_button, 1)
        queue_buttons.addWidget(self.batch_stop_button, 1)
        queue_buttons.addWidget(clear_button, 1)
        queue_layout.addLayout(queue_buttons)
        footnote = QtWidgets.QLabel("Здесь можно собрать отдельную очередь вручную, не затрагивая основной экран Stories.")
        footnote.setObjectName("footnoteLabel")
        footnote.setWordWrap(True)
        queue_layout.addWidget(footnote)

        left_host = QtWidgets.QWidget()
        left_host.setLayout(left_column)
        right_host = QtWidgets.QWidget()
        right_layout = QtWidgets.QVBoxLayout(right_host)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.addWidget(queue_card)

        content_row.addWidget(left_host, 2)
        content_row.addWidget(right_host, 3)
        layout.addLayout(content_row, 1)
        return page

    def _home2_composer_card(self) -> QtWidgets.QWidget:
        card = self._card("Профили для скачивания")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(12))
        layout.addWidget(self._section_caption("Профили для скачивания"))

        note = QtWidgets.QLabel("Добавь профили, выбери настройки и запусти одной кнопкой.")
        note.setWordWrap(True)
        note.setObjectName("cardHint")
        layout.addWidget(note)

        input_shell = QtWidgets.QFrame()
        input_shell.setObjectName("inputShell")
        input_layout = QtWidgets.QGridLayout(input_shell)
        input_layout.setContentsMargins(0, 0, 0, 0)
        input_layout.setSpacing(0)

        self.home2_batch_input = QtWidgets.QPlainTextEdit()
        self.home2_batch_input.setObjectName("profileEditor")
        self.home2_batch_input.setPlaceholderText(
            "По одной ссылке или username на строку.\nНапример:\ndian.vegas1\nhttps://www.instagram.com/stevensetu/\nleftlanepapi"
        )
        self.home2_batch_input.setMinimumHeight(scaled(140))
        self.home2_batch_input.setTabChangesFocus(False)
        input_layout.addWidget(self.home2_batch_input, 0, 0)

        self.home2_clear_input_button = QtWidgets.QToolButton(input_shell)
        self.home2_clear_input_button.setObjectName("inlineClearButton")
        self.home2_clear_input_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_DialogCloseButton))
        self.home2_clear_input_button.setAutoRaise(True)
        self.home2_clear_input_button.setCursor(QtCore.Qt.PointingHandCursor)
        self.home2_clear_input_button.clicked.connect(self.clear_home2_input)
        self.home2_clear_input_button.hide()
        input_layout.addWidget(self.home2_clear_input_button, 0, 0, QtCore.Qt.AlignTop | QtCore.Qt.AlignRight)

        self.home2_input_counter = QtWidgets.QLabel("0 профилей", input_shell)
        self.home2_input_counter.setObjectName("inputCounter")
        input_layout.addWidget(self.home2_input_counter, 0, 0, QtCore.Qt.AlignBottom | QtCore.Qt.AlignRight)
        self.home2_batch_input.textChanged.connect(self._update_home2_input_overlay)
        layout.addWidget(input_shell)

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(scaled(8))
        add_button = QtWidgets.QPushButton("Добавить")
        add_button.setProperty("secondary", True)
        add_button.setObjectName("prominentSecondaryButton")
        add_button.clicked.connect(self.add_batch_profiles_from_home2)
        remember_button = QtWidgets.QPushButton("Запомнить")
        remember_button.setProperty("secondary", True)
        remember_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_DialogSaveButton))
        remember_button.clicked.connect(self.remember_current_batch_list)
        clear_button = QtWidgets.QPushButton("Очистить")
        clear_button.setProperty("secondary", True)
        clear_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_DialogResetButton))
        clear_button.clicked.connect(self.clear_home2_input)
        row.addWidget(add_button, 1)
        row.addWidget(remember_button, 1)
        row.addWidget(clear_button, 1)
        layout.addLayout(row)

        actions = QtWidgets.QHBoxLayout()
        actions.setSpacing(scaled(8))
        run_button = QtWidgets.QPushButton("Скачать")
        run_button.setObjectName("queueActionButton")
        run_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_ArrowDown))
        run_button.clicked.connect(self.start_batch)
        self.home2_run_button = run_button
        stop_button = QtWidgets.QPushButton("Остановить")
        stop_button.setObjectName("subtleDangerButton")
        stop_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_BrowserStop))
        stop_button.clicked.connect(self.stop_batch)
        stop_button.setEnabled(False)
        self.home2_stop_button = stop_button
        actions.addWidget(run_button, 1)
        actions.addWidget(stop_button, 1)
        layout.addLayout(actions)

        layout.addWidget(self._home2_browser_mode_card())
        layout.addWidget(self._home2_media_mode_card())
        layout.addWidget(self._save_directory_card(home2_mode=True))

        tip = QtWidgets.QLabel("Вставь профили, выбери режим и папку — затем нажми «Скачать».")
        tip.setObjectName("footnoteLabel")
        tip.setWordWrap(True)
        layout.addWidget(tip)
        self._update_home2_input_overlay()
        return card

    def _home2_queue_card(self) -> QtWidgets.QWidget:
        card = self._card("Очередь")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(12))
        layout.addWidget(self._section_caption("Очередь"))

        stats = QtWidgets.QHBoxLayout()
        stats.setSpacing(scaled(6))
        self.home2_queue_count = self._badge_label("В очереди: 0")
        self.home2_recent_count = self._badge_label(f"Наборов: {len(self.recent_lists)}")
        self.home2_mode_label = self._badge_label(f"Режим: {'В фоне' if self.download_mode == 'background' else 'Видимо'}")
        self.home2_media_label = self._badge_label(
            f"Контент: {'Только видео' if self.media_filter == 'video_only' else 'Фото и видео'}"
        )
        stats.addWidget(self.home2_queue_count)
        stats.addWidget(self.home2_recent_count)
        stats.addWidget(self.home2_mode_label)
        stats.addWidget(self.home2_media_label)
        stats.addStretch(1)
        layout.addLayout(stats)

        self.home2_progress_bar = QtWidgets.QProgressBar()
        self.home2_progress_bar.setObjectName("queueProgressBar")
        self.home2_progress_bar.setTextVisible(False)
        self.home2_progress_bar.setMinimum(0)
        self.home2_progress_bar.setMaximum(1)
        self.home2_progress_bar.setValue(0)
        self.home2_progress_bar.setVisible(False)
        layout.addWidget(self.home2_progress_bar)

        self.home2_progress_label = QtWidgets.QLabel("Пока пусто. Добавь профили выше или выбери недавний набор справа.")
        self.home2_progress_label.setWordWrap(True)
        self.home2_progress_label.setObjectName("cardHint")
        layout.addWidget(self.home2_progress_label)

        self.home2_batch_table = QtWidgets.QTableWidget(0, 3)
        self.home2_batch_table.setObjectName("queueTable")
        self.home2_batch_table.setHorizontalHeaderLabels(["Профиль", "Статус", "Сообщение"])
        self.home2_batch_table.horizontalHeader().setStretchLastSection(True)
        self.home2_batch_table.horizontalHeader().setSectionResizeMode(0, QtWidgets.QHeaderView.Stretch)
        self.home2_batch_table.horizontalHeader().setSectionResizeMode(1, QtWidgets.QHeaderView.ResizeToContents)
        self.home2_batch_table.verticalHeader().setVisible(False)
        self.home2_batch_table.verticalHeader().setDefaultSectionSize(scaled(28))
        self.home2_batch_table.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.home2_batch_table.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.home2_batch_table.setAlternatingRowColors(True)
        self.home2_batch_table.setMinimumHeight(240)
        layout.addWidget(self.home2_batch_table)

        row = QtWidgets.QHBoxLayout()
        clear_button = QtWidgets.QPushButton("Очистить очередь")
        clear_button.setProperty("secondary", True)
        clear_button.setObjectName("subtleDangerButton")
        clear_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_TrashIcon))
        clear_button.clicked.connect(self.clear_batch)
        clear_button.setEnabled(False)
        self.home2_clear_button = clear_button
        row.addWidget(clear_button)
        row.addStretch(1)
        layout.addLayout(row)

        footnote = QtWidgets.QLabel("После запуска список сохранится в «Недавних наборах».")
        footnote.setObjectName("footnoteLabel")
        footnote.setWordWrap(True)
        layout.addWidget(footnote)
        return card

    def _home2_recent_lists_card(self) -> QtWidgets.QWidget:
        card = self._card("Недавние наборы")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(10))
        layout.addWidget(self._section_caption("Недавние наборы"))
        self.home2_recent_lists_container = QtWidgets.QVBoxLayout()
        self.home2_recent_lists_container.setSpacing(scaled(10))
        layout.addLayout(self.home2_recent_lists_container)
        self.home2_recent_toggle = QtWidgets.QPushButton("Показать ещё ↓")
        self.home2_recent_toggle.setProperty("secondary", True)
        self.home2_recent_toggle.clicked.connect(self.toggle_home2_recent_lists)
        self.home2_recent_toggle.setVisible(False)
        layout.addWidget(self.home2_recent_toggle, 0, QtCore.Qt.AlignLeft)
        return card

    def _home2_status_card(self) -> QtWidgets.QWidget:
        card = self._card("Состояние")
        card.setObjectName("statusCard")
        card.setProperty("statusTone", "idle")
        self.home2_status_card_frame = card
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(10))
        layout.addWidget(self._section_caption("Состояние"))

        self.status_title_label = QtWidgets.QLabel("Ожидание")
        self.status_detail_label = QtWidgets.QLabel("Приложение готово к работе.")
        self.status_detail_label.setWordWrap(True)

        badge_row = QtWidgets.QHBoxLayout()
        badge_row.setContentsMargins(0, 0, 0, 0)
        self.home2_status_badge = QtWidgets.QLabel("Ожидание")
        self.home2_status_badge.setObjectName("statusBadge")
        badge_row.addWidget(self.home2_status_badge, 0, QtCore.Qt.AlignLeft)
        badge_row.addStretch(1)
        layout.addLayout(badge_row)

        self.home2_status_summary = QtWidgets.QLabel("Приложение готово к работе.")
        self.home2_status_summary.setWordWrap(True)
        layout.addWidget(self.home2_status_summary)

        step_box = QtWidgets.QFrame()
        step_box.setObjectName("stepCard")
        step_layout = QtWidgets.QVBoxLayout(step_box)
        step_layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        step_layout.setSpacing(scaled(4))
        step_title = self._section_caption("Текущий шаг")
        self.home2_step_value = QtWidgets.QLabel("Ожидание команды.")
        self.home2_step_value.setWordWrap(True)
        step_layout.addWidget(step_title)
        step_layout.addWidget(self.home2_step_value)
        layout.addWidget(step_box)
        return card

    def _home2_result_card(self) -> QtWidgets.QWidget:
        card = self._card("Результат")
        layout = QtWidgets.QGridLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(10))
        layout.addWidget(self._section_caption("Результат"), 0, 0, 1, 2)

        self.found_label = QtWidgets.QLabel("Найдено: 0")
        self.saved_label = QtWidgets.QLabel("Сохранено: 0")
        self.home2_profiles_value = QtWidgets.QLabel("0")
        self.home2_saved_value = QtWidgets.QLabel("0")
        self.home2_files_value = QtWidgets.QLabel("0")
        self.home2_folders_value = QtWidgets.QLabel("0")

        tiles = [
            (self.home2_profiles_value, "Профилей", "#f6a04d"),
            (self.home2_saved_value, "Сохранено", "#65c466"),
            (self.home2_files_value, "Файлов", "#54a6ff"),
            (self.home2_folders_value, "Папок", "#34c9bf"),
        ]
        for index, (value_label, title, color) in enumerate(tiles):
            layout.addWidget(self._metric_tile(value_label, title, color), (index // 2) + 1, index % 2)
        return card

    def _home2_activity_card(self) -> QtWidgets.QWidget:
        card = self._card("Журнал")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(10))
        layout.addWidget(self._section_caption("Журнал"))

        self.downloads_list = QtWidgets.QListWidget()
        self.downloads_list.setObjectName("downloadsList")
        self.downloads_list.itemDoubleClicked.connect(self.open_download_item)
        self.downloads_list.setSpacing(6)
        self.downloads_list.setUniformItemSizes(False)
        self.downloads_list.setMinimumHeight(scaled(120))
        layout.addWidget(self._group("Последние загрузки", self.downloads_list))

        self.home2_logs_text = QtWidgets.QPlainTextEdit()
        self.home2_logs_text.setObjectName("logsText")
        self.home2_logs_text.setReadOnly(True)
        self.home2_logs_text.setMinimumHeight(scaled(180))
        self.logs_text = self.home2_logs_text
        layout.addWidget(self._group("Логи", self.home2_logs_text))

        self.home2_last_result = QtWidgets.QLabel("Пока нет действий.")
        self.home2_last_result.setWordWrap(True)
        self.activity_subtitle = self.home2_last_result
        self.home2_session_summary = QtWidgets.QLabel("Состояние сессии неизвестно.")
        self.home2_session_summary.setWordWrap(True)
        self.home2_worker_summary = QtWidgets.QLabel("Воркер ещё не проверялся.")
        self.home2_worker_summary.setWordWrap(True)
        layout.addWidget(self._group("Последнее событие", self.home2_last_result))
        layout.addWidget(self._group("Сессия", self.home2_session_summary))
        layout.addWidget(self._group("Воркер", self.home2_worker_summary))
        return card

    def _home2_browser_mode_card(self) -> QtWidgets.QWidget:
        options = [
            ("В фоне", "Браузер скрыт, работает незаметно", "background"),
            ("Видимо", "Открывается окно Chromium, можно наблюдать", "visible"),
        ]
        return self._segmented_option_card(
            "Режим браузера",
            options,
            "home2_mode_combo",
            "home2_mode_description",
            self.download_mode,
            self.on_mode_changed,
        )

    def _home2_media_mode_card(self) -> QtWidgets.QWidget:
        options = [
            ("Фото и видео", "Скачиваются все сторис", "all"),
            ("Только видео", "Фото пропускаются", "video_only"),
        ]
        return self._segmented_option_card(
            "Что сохранять",
            options,
            "home2_media_combo",
            "home2_media_description",
            self.media_filter,
            self.on_media_filter_changed,
        )

    def _summary_pill(self, title: str, value_label: QtWidgets.QLabel) -> QtWidgets.QWidget:
        host = self._card(title)
        layout = QtWidgets.QVBoxLayout(host)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.addWidget(self._section_caption(title))
        value_label.setWordWrap(True)
        layout.addWidget(value_label)
        return host

    def _group(self, title: str, content: QtWidgets.QWidget) -> QtWidgets.QWidget:
        box = QtWidgets.QFrame()
        box.setObjectName("subCard")
        box_layout = QtWidgets.QVBoxLayout(box)
        box_layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        box_layout.setSpacing(scaled(8))
        box_layout.addWidget(self._section_caption(title))
        box_layout.addWidget(content)
        return box

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

    def _hero(self, title: str, subtitle: str, *, supporting: str | None = None) -> QtWidgets.QWidget:
        host = self._card("")
        layout = QtWidgets.QVBoxLayout(host)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(6))

        header_row = QtWidgets.QHBoxLayout()
        header_row.setContentsMargins(0, 0, 0, 0)
        header_row.setSpacing(10)
        title_label = QtWidgets.QLabel(title)
        title_label.setObjectName("heroTitle")
        header_row.addWidget(title_label, 0, QtCore.Qt.AlignLeft)
        header_row.addStretch(1)
        version_label = QtWidgets.QLabel(QtWidgets.QApplication.applicationVersion() or app_version())
        version_label.setObjectName("heroVersion")
        header_row.addWidget(version_label, 0, QtCore.Qt.AlignRight)
        layout.addLayout(header_row)

        subtitle_label = QtWidgets.QLabel(subtitle)
        subtitle_label.setWordWrap(True)
        subtitle_label.setObjectName("heroSubtitle")
        layout.addWidget(subtitle_label)

        supporting_text = supporting or "Добавь профили, выбери настройки и запусти одной кнопкой."
        supporting_label = QtWidgets.QLabel(supporting_text)
        supporting_label.setWordWrap(True)
        supporting_label.setObjectName("cardHint")
        layout.addWidget(supporting_label)
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

    def _save_directory_card(self, *, batch_mode: bool = False, home2_mode: bool = False, reels_mode: bool = False) -> QtWidgets.QWidget:
        box = self._card("Папка для сохранения")
        layout = QtWidgets.QVBoxLayout(box)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.addWidget(self._section_caption("Папка для сохранения"))
        line_edit = QtWidgets.QLineEdit(str(self.save_directory))
        line_edit.setObjectName("pathField")
        line_edit.setReadOnly(True)
        line_edit.setAlignment(QtCore.Qt.AlignRight | QtCore.Qt.AlignVCenter)
        line_edit.setCursorPosition(len(str(self.save_directory)))
        layout.addWidget(line_edit)

        button_row = QtWidgets.QHBoxLayout()
        button_row.setSpacing(scaled(8))
        choose = QtWidgets.QPushButton("Выбрать папку")
        choose.setProperty("secondary", True)
        choose.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_DialogOpenButton))
        choose.clicked.connect(lambda: self.choose_save_directory(line_edit))
        show = QtWidgets.QPushButton("Показать в проводнике")
        show.setProperty("secondary", True)
        show.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_DirOpenIcon))
        show.clicked.connect(self.open_save_directory)
        button_row.addWidget(choose, 1)
        button_row.addWidget(show, 1)
        layout.addLayout(button_row)

        if reels_mode:
            self.reels_directory_line = line_edit
        elif home2_mode:
            self.home2_directory_line = line_edit
        elif batch_mode:
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

    def _mode_card(self, *, batch_mode: bool = False, home2_mode: bool = False) -> QtWidgets.QWidget:
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
        media_label = QtWidgets.QLabel("Что сохранять")
        media_label.setObjectName("sectionLabel")
        media_combo = QtWidgets.QComboBox()
        media_combo.addItem("Фото и видео", "all")
        media_combo.addItem("Только видео", "video_only")
        media_combo.setCurrentIndex(0 if self.media_filter == "all" else 1)
        media_combo.currentIndexChanged.connect(self.on_media_filter_changed)
        media_detail = QtWidgets.QLabel("Можно сохранять все найденные stories или пропускать фото и оставлять только видео.")
        media_detail.setWordWrap(True)

        layout.addWidget(label)
        layout.addWidget(combo)
        layout.addWidget(detail)
        layout.addWidget(media_label)
        layout.addWidget(media_combo)
        layout.addWidget(media_detail)

        if home2_mode:
            self.home2_mode_combo = combo
            self.home2_media_combo = media_combo
        elif batch_mode:
            self.batch_mode_combo = combo
            self.batch_media_combo = media_combo
        else:
            self.mode_combo = combo
            self.media_combo = media_combo
        return host

    def _reels_status_card(self) -> QtWidgets.QWidget:
        card = self._card("Состояние")
        card.setObjectName("statusCard")
        card.setProperty("statusTone", "idle")
        self.reels_status_card_frame = card
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(10))
        layout.addWidget(self._section_caption("Состояние"))
        self.reels_status_badge = QtWidgets.QLabel("Ожидание")
        self.reels_status_badge.setObjectName("statusBadge")
        layout.addWidget(self.reels_status_badge, 0, QtCore.Qt.AlignLeft)
        self.reels_status_summary = QtWidgets.QLabel("Приложение готово к работе.")
        self.reels_status_summary.setWordWrap(True)
        layout.addWidget(self.reels_status_summary)
        return card

    def _reels_downloads_card(self) -> QtWidgets.QWidget:
        card = self._card("Последние загрузки")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(10))
        layout.addWidget(self._section_caption("Последние загрузки"))
        self.reels_downloads_list = QtWidgets.QListWidget()
        self.reels_downloads_list.setObjectName("downloadsList")
        self.reels_downloads_list.itemDoubleClicked.connect(self.open_download_item)
        self.reels_downloads_list.setSpacing(6)
        self.reels_downloads_list.setMinimumHeight(scaled(150))
        layout.addWidget(self.reels_downloads_list)
        return card

    def _reels_logs_card(self) -> QtWidgets.QWidget:
        card = self._card("Логи")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(10))
        header = QtWidgets.QHBoxLayout()
        header.setContentsMargins(0, 0, 0, 0)
        header.addWidget(self._section_caption("Логи"))
        header.addStretch(1)
        self.reels_copy_logs_button = QtWidgets.QPushButton("Скопировать")
        self.reels_copy_logs_button.setProperty("secondary", True)
        self.reels_copy_logs_button.clicked.connect(self._copy_reels_logs)
        header.addWidget(self.reels_copy_logs_button)
        layout.addLayout(header)
        self.reels_logs_text = QtWidgets.QPlainTextEdit()
        self.reels_logs_text.setObjectName("logsText")
        self.reels_logs_text.setReadOnly(True)
        self.reels_logs_text.setMinimumHeight(scaled(180))
        layout.addWidget(self.reels_logs_text)
        return card

    def _apply_styles(self) -> None:
        app = QtWidgets.QApplication.instance()
        if app is not None:
            app.setStyleSheet(self._theme_stylesheet())

    def _card(self, title: str) -> QtWidgets.QFrame:
        del title
        card = QtWidgets.QFrame()
        card.setObjectName("cardSurface")
        return card

    def _section_caption(self, text: str) -> QtWidgets.QLabel:
        label = QtWidgets.QLabel(text)
        label.setObjectName("sectionLabel")
        return label

    def _build_nav_button(self, symbol: str, text: str, detail: str) -> QtWidgets.QPushButton:
        button = QtWidgets.QPushButton(f"{symbol}  {text}\n{self._nav_subtitle(detail)}")
        button.setCheckable(True)
        button.setProperty("nav", True)
        button.setToolTip(detail)
        return button

    def _build_footer_button(self, text: str, icon_kind: QtWidgets.QStyle.StandardPixmap) -> QtWidgets.QPushButton:
        button = QtWidgets.QPushButton(text)
        button.setProperty("secondary", True)
        button.setIcon(self.style().standardIcon(icon_kind))
        return button

    def _badge_label(self, text: str) -> QtWidgets.QLabel:
        label = QtWidgets.QLabel(text)
        label.setProperty("badge", True)
        return label

    def _metric_tile(self, value_label: QtWidgets.QLabel, title: str, color: str) -> QtWidgets.QWidget:
        tile = QtWidgets.QFrame()
        tile.setObjectName("metricTile")
        layout = QtWidgets.QVBoxLayout(tile)
        layout.setContentsMargins(scaled(12), scaled(12), scaled(12), scaled(12))
        layout.setSpacing(scaled(6))

        title_row = QtWidgets.QHBoxLayout()
        title_row.setContentsMargins(0, 0, 0, 0)
        title_row.setSpacing(scaled(6))
        dot = QtWidgets.QLabel("●")
        dot.setObjectName("metricDot")
        dot.setStyleSheet(f"color: {color};")
        caption = QtWidgets.QLabel(title)
        caption.setObjectName("metricTitle")
        title_row.addWidget(dot, 0, QtCore.Qt.AlignLeft)
        title_row.addWidget(caption, 0, QtCore.Qt.AlignLeft)
        title_row.addStretch(1)

        value_label.setObjectName("metricValue")
        layout.addLayout(title_row)
        layout.addWidget(value_label)
        return tile

    def _segmented_option_card(
        self,
        title: str,
        options: list[tuple[str, str, str]],
        combo_attr: str,
        description_attr: str,
        current_value: str,
        change_handler,
    ) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(scaled(8))
        layout.addWidget(self._section_caption(title))

        group = QtWidgets.QFrame()
        group.setObjectName("segmentedGroup")
        row = QtWidgets.QHBoxLayout(group)
        row.setContentsMargins(scaled(3), scaled(3), scaled(3), scaled(3))
        row.setSpacing(scaled(4))
        combo = QtWidgets.QComboBox()
        combo.hide()
        buttons: list[QtWidgets.QPushButton] = []
        for index, (button_text, _, value) in enumerate(options):
            combo.addItem(button_text, value)
            button = QtWidgets.QPushButton(button_text)
            button.setCheckable(True)
            button.setProperty("segmented", True)
            button.clicked.connect(lambda checked=False, i=index, target=combo: target.setCurrentIndex(i))
            row.addWidget(button, 1)
            buttons.append(button)
        combo.currentIndexChanged.connect(change_handler)
        layout.addWidget(group)
        layout.addWidget(combo)

        description = QtWidgets.QLabel("")
        description.setWordWrap(True)
        description.setObjectName("cardHint")
        setattr(self, description_attr, description)
        layout.addWidget(description)
        setattr(self, combo_attr, combo)

        current_index = 0
        for index, (_, _, value) in enumerate(options):
            if value == current_value:
                current_index = index
                break
        combo.setCurrentIndex(current_index)
        for index, button in enumerate(buttons):
            button.setChecked(index == current_index)

        def sync_button_state(index: int) -> None:
            for button_index, button in enumerate(buttons):
                button.setChecked(button_index == index)
            description.setText(options[index][1])

        combo.currentIndexChanged.connect(sync_button_state)
        sync_button_state(current_index)
        return host

    def _update_home2_input_overlay(self) -> None:
        if not hasattr(self, "home2_batch_input"):
            return
        count = len(parse_batch_links(self.home2_batch_input.toPlainText()))
        suffix = "профиль" if count == 1 else "профилей"
        if hasattr(self, "home2_input_counter"):
            self.home2_input_counter.setText(f"{count} {suffix}")
        if hasattr(self, "home2_clear_input_button"):
            self.home2_clear_input_button.setVisible(bool(self.home2_batch_input.toPlainText().strip()))

    def _update_reels_input_overlay(self) -> None:
        if not hasattr(self, "reels_input"):
            return
        lines = [line.strip() for line in self.reels_input.toPlainText().splitlines() if line.strip()]
        count = len(lines)
        suffix = "ссылка" if count == 1 else "ссылок"
        if hasattr(self, "reels_input_counter"):
            self.reels_input_counter.setText(f"{count} {suffix}")
        if hasattr(self, "reels_clear_input_button"):
            self.reels_clear_input_button.setVisible(bool(self.reels_input.toPlainText().strip()))

    def _copy_reels_logs(self) -> None:
        if not hasattr(self, "reels_logs_text"):
            return
        QtWidgets.QApplication.clipboard().setText(self.reels_logs_text.toPlainText())
        self.reels_copy_logs_button.setText("Скопировано ✓")
        QtCore.QTimer.singleShot(1200, lambda: self.reels_copy_logs_button.setText("Скопировать"))

    def _sync_navigation_state(self, index: int) -> None:
        button = self.nav_group.button(index)
        if button is not None and not button.isChecked():
            button.setChecked(True)
