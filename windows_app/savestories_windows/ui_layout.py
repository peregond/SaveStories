from __future__ import annotations

from PySide6 import QtCore, QtWidgets

from .ui_support import SettingsDialog, app_version


class MainWindowLayoutMixin:
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
        self.stack.addWidget(self._wrap_scroll_area(self._build_home_two_page()))
        self.stack.addWidget(self._wrap_scroll_area(self._build_batch_page()))
        self.stack.addWidget(self._wrap_scroll_area(self._build_reels_page()))
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
        subtitle = QtWidgets.QLabel("STORIES DOWNLOADER")
        subtitle.setObjectName("sidebarSubtitle")
        layout.addWidget(title)
        layout.addWidget(subtitle)

        self.nav_group = QtWidgets.QButtonGroup(self)
        self.nav_group.setExclusive(True)

        for index, (text, detail) in enumerate(
            [
                ("Главная", "Основной стартовый сценарий"),
                ("Списочная", "Очередь профилей"),
                ("Reels", "Скоро появится"),
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

    def _build_reels_page(self) -> QtWidgets.QWidget:
        page = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(18)

        layout.addWidget(
            self._hero(
                "Reels",
                "Отдельный сценарий для выгрузки Reels появится в следующих версиях.",
            )
        )

        card = QtWidgets.QGroupBox("Что будет дальше")
        card_layout = QtWidgets.QVBoxLayout(card)
        text = QtWidgets.QLabel(
            "Здесь появится отдельный поток работы с Reels: вставка ссылок, пакетная выгрузка и более точные фильтры контента."
        )
        text.setWordWrap(True)
        card_layout.addWidget(text)
        for line in [
            "Отдельная очередь ссылок на Reels.",
            "Пакетная выгрузка с понятным прогрессом.",
            "Более точные фильтры под видео-контент.",
        ]:
            bullet = QtWidgets.QLabel(f"• {line}")
            bullet.setWordWrap(True)
            card_layout.addWidget(bullet)

        layout.addWidget(card)
        layout.addStretch(1)
        return page

    def _build_home_two_page(self) -> QtWidgets.QWidget:
        page = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(18)

        layout.addWidget(
            self._hero(
                "Главная",
                "Более удобный стартовый экран: собери список профилей, сохрани его как недавний и запускай выгрузку без лишних переключений.",
            )
        )
        layout.addWidget(self._home2_status_strip())

        content_row = QtWidgets.QHBoxLayout()
        content_row.setSpacing(18)

        left_column = QtWidgets.QVBoxLayout()
        left_column.setSpacing(18)
        left_column.addWidget(self._home2_composer_card())
        left_column.addWidget(self._home2_queue_card(), 1)

        right_column = QtWidgets.QVBoxLayout()
        right_column.setSpacing(18)
        right_column.addWidget(self._home2_recent_lists_card())
        right_column.addWidget(self._home2_compact_activity_card())
        right_column.addStretch(1)

        left_host = QtWidgets.QWidget()
        left_host.setLayout(left_column)
        right_host = QtWidgets.QWidget()
        right_host.setLayout(right_column)
        right_host.setFixedWidth(320)

        content_row.addWidget(left_host, 1)
        content_row.addWidget(right_host)
        layout.addLayout(content_row, 1)
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

    def _home2_status_strip(self) -> QtWidgets.QWidget:
        host = QtWidgets.QWidget()
        layout = QtWidgets.QHBoxLayout(host)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(12)

        self.home2_status_label = QtWidgets.QLabel()
        self.home2_step_label = QtWidgets.QLabel()
        self.home2_result_label = QtWidgets.QLabel()
        self.home2_live_label = QtWidgets.QLabel()

        for widget in [
            self._summary_pill("Состояние", self.home2_status_label),
            self._summary_pill("Текущий шаг", self.home2_step_label),
            self._summary_pill("Результат", self.home2_result_label),
            self._summary_pill("В выбранной папке", self.home2_live_label),
        ]:
            layout.addWidget(widget, 1)

        return host

    def _home2_composer_card(self) -> QtWidgets.QWidget:
        card = QtWidgets.QGroupBox("Быстрый старт")
        layout = QtWidgets.QVBoxLayout(card)

        note = QtWidgets.QLabel(
            "Вставь usernames или ссылки, сохрани список в недавние и запускай очередь прямо отсюда. Этот экран собран как основной сценарий для новых пользователей."
        )
        note.setWordWrap(True)
        layout.addWidget(note)

        self.home2_batch_input = QtWidgets.QPlainTextEdit()
        self.home2_batch_input.setPlaceholderText(
            "По одной ссылке или username на строку.\nНапример:\ndian.vegas1\nhttps://www.instagram.com/stevensetu/\nleftlanepapi"
        )
        self.home2_batch_input.setFixedHeight(140)
        layout.addWidget(self.home2_batch_input)

        row = QtWidgets.QHBoxLayout()
        add_button = QtWidgets.QPushButton("Добавить")
        add_button.clicked.connect(self.add_batch_profiles_from_home2)
        remember_button = QtWidgets.QPushButton("Запомнить")
        remember_button.clicked.connect(self.remember_current_batch_list)
        clear_button = QtWidgets.QPushButton("Очистить")
        clear_button.clicked.connect(self.clear_home2_input)
        row.addWidget(add_button)
        row.addWidget(remember_button)
        row.addWidget(clear_button)
        layout.addLayout(row)

        actions = QtWidgets.QVBoxLayout()
        actions.setSpacing(10)
        run_button = QtWidgets.QPushButton("Скачать")
        run_button.setObjectName("queueActionButton")
        run_button.clicked.connect(self.start_batch)
        self.home2_run_button = run_button
        stop_button = QtWidgets.QPushButton("Остановить")
        stop_button.clicked.connect(self.stop_batch)
        stop_button.setEnabled(False)
        self.home2_stop_button = stop_button
        actions.addWidget(run_button)
        actions.addWidget(stop_button)
        layout.addLayout(actions)

        layout.addWidget(self._mode_card(home2_mode=True))

        lower = QtWidgets.QHBoxLayout()
        lower.setSpacing(14)
        lower.addWidget(self._save_directory_card(home2_mode=True), 1)

        tip_box = QtWidgets.QGroupBox("Совет")
        tip_layout = QtWidgets.QVBoxLayout(tip_box)
        tip = QtWidgets.QLabel("Для первых тестов используй режим «Видимо». Если всё стабильно, переключайся на фон.")
        tip.setWordWrap(True)
        tip_layout.addWidget(tip)
        lower.addWidget(tip_box, 1)
        layout.addLayout(lower)
        return card

    def _home2_queue_card(self) -> QtWidgets.QWidget:
        card = QtWidgets.QGroupBox("Очередь и прогресс")
        layout = QtWidgets.QVBoxLayout(card)

        stats = QtWidgets.QHBoxLayout()
        self.home2_queue_count = QtWidgets.QLabel("В очереди: 0")
        self.home2_recent_count = QtWidgets.QLabel(f"Недавних наборов: {len(self.recent_lists)}")
        self.home2_mode_label = QtWidgets.QLabel(f"Режим: {'В фоне' if self.download_mode == 'background' else 'Видимо'}")
        self.home2_media_label = QtWidgets.QLabel(f"Контент: {'Только видео' if self.media_filter == 'video_only' else 'Фото и видео'}")
        stats.addWidget(self.home2_queue_count)
        stats.addWidget(self.home2_recent_count)
        stats.addWidget(self.home2_mode_label)
        stats.addWidget(self.home2_media_label)
        stats.addStretch(1)
        layout.addLayout(stats)

        self.home2_progress_label = QtWidgets.QLabel("Список пока пустой.")
        self.home2_progress_label.setWordWrap(True)
        layout.addWidget(self.home2_progress_label)

        self.home2_batch_table = QtWidgets.QTableWidget(0, 3)
        self.home2_batch_table.setHorizontalHeaderLabels(["Профиль", "Статус", "Сообщение"])
        self.home2_batch_table.horizontalHeader().setStretchLastSection(True)
        self.home2_batch_table.horizontalHeader().setSectionResizeMode(0, QtWidgets.QHeaderView.Stretch)
        self.home2_batch_table.horizontalHeader().setSectionResizeMode(1, QtWidgets.QHeaderView.ResizeToContents)
        self.home2_batch_table.verticalHeader().setVisible(False)
        self.home2_batch_table.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.home2_batch_table.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.home2_batch_table.setMinimumHeight(240)
        layout.addWidget(self.home2_batch_table)

        row = QtWidgets.QHBoxLayout()
        clear_button = QtWidgets.QPushButton("Очистить очередь")
        clear_button.clicked.connect(self.clear_batch)
        clear_button.setEnabled(False)
        self.home2_clear_button = clear_button
        row.addWidget(clear_button)
        row.addStretch(1)
        layout.addLayout(row)
        return card

    def _home2_recent_lists_card(self) -> QtWidgets.QWidget:
        card = QtWidgets.QGroupBox("Недавнее")
        layout = QtWidgets.QVBoxLayout(card)
        self.home2_recent_lists_container = QtWidgets.QVBoxLayout()
        self.home2_recent_lists_container.setSpacing(10)
        layout.addLayout(self.home2_recent_lists_container)
        self.home2_recent_toggle = QtWidgets.QPushButton("Ещё")
        self.home2_recent_toggle.clicked.connect(self.toggle_home2_recent_lists)
        self.home2_recent_toggle.setVisible(False)
        layout.addWidget(self.home2_recent_toggle, 0, QtCore.Qt.AlignLeft)
        return card

    def _home2_compact_activity_card(self) -> QtWidgets.QWidget:
        card = QtWidgets.QGroupBox("Логи и активность")
        layout = QtWidgets.QVBoxLayout(card)
        self.home2_logs_text = QtWidgets.QPlainTextEdit()
        self.home2_logs_text.setReadOnly(True)
        self.home2_logs_text.setFixedHeight(150)
        layout.addWidget(self._group("Логи", self.home2_logs_text))
        self.home2_last_result = QtWidgets.QLabel("Пока нет действий.")
        self.home2_last_result.setWordWrap(True)
        self.home2_session_summary = QtWidgets.QLabel("Состояние сессии неизвестно.")
        self.home2_session_summary.setWordWrap(True)
        self.home2_worker_summary = QtWidgets.QLabel("Воркер ещё не проверялся.")
        self.home2_worker_summary.setWordWrap(True)
        layout.addWidget(self._group("Последнее событие", self.home2_last_result))
        layout.addWidget(self._group("Сессия", self.home2_session_summary))
        layout.addWidget(self._group("Воркер", self.home2_worker_summary))
        return card

    def _summary_pill(self, title: str, value_label: QtWidgets.QLabel) -> QtWidgets.QWidget:
        host = QtWidgets.QGroupBox(title)
        layout = QtWidgets.QVBoxLayout(host)
        value_label.setWordWrap(True)
        layout.addWidget(value_label)
        return host

    def _group(self, title: str, content: QtWidgets.QWidget) -> QtWidgets.QWidget:
        box = QtWidgets.QGroupBox(title)
        box_layout = QtWidgets.QVBoxLayout(box)
        box_layout.setContentsMargins(12, 12, 12, 12)
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

    def _save_directory_card(self, *, batch_mode: bool = False, home2_mode: bool = False) -> QtWidgets.QWidget:
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

        if home2_mode:
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
            QPushButton#applyUpdateButton {
                background: #f29d38;
                color: #1c1c1c;
                border: 1px solid #d8872a;
                border-radius: 12px;
                font-size: 14px;
                font-weight: 700;
                padding: 10px 12px;
            }
            QPushButton#applyUpdateButton:hover {
                background: #ffab45;
            }
            QPushButton#applyUpdateButton:pressed {
                background: #e2871f;
            }
            QPushButton#applyUpdateButton:disabled {
                background: #f0cda4;
                color: #6c6c6c;
                border-color: #d8b890;
            }
            QPushButton#queueActionButton {
                background: #5c8d71;
                color: white;
                border: 1px solid #537f66;
            }
            QPushButton#queueActionButton:hover {
                background: #527f65;
                border-color: #496f59;
            }
            QPushButton#queueActionButton:pressed {
                background: #476e57;
                border-color: #3f624e;
            }
            QPushButton#queueActionButton:disabled {
                background: #aec0b5;
                color: #eef3f0;
                border-color: #aec0b5;
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
