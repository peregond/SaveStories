from __future__ import annotations

from PySide6 import QtCore, QtGui, QtWidgets

from .ui_support import SettingsDialog, app_version


class MainWindowLayoutMixin:
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
        content_layout.setContentsMargins(24, 22, 24, 22)
        content_layout.setSpacing(22)
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
        self.settings_dialog.open_runtime_requested.connect(self.open_runtime_directory)
        self.settings_dialog.prevent_sleep_toggled.connect(self.set_prevent_sleep_during_downloads)

    def _build_sidebar(self) -> QtWidgets.QWidget:
        sidebar = QtWidgets.QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(252)

        layout = QtWidgets.QVBoxLayout(sidebar)
        layout.setContentsMargins(14, 18, 14, 14)
        layout.setSpacing(10)

        brand = QtWidgets.QFrame()
        brand.setObjectName("navBrand")
        brand_layout = QtWidgets.QVBoxLayout(brand)
        brand_layout.setContentsMargins(10, 10, 10, 10)
        brand_layout.setSpacing(2)

        title = QtWidgets.QLabel("SaveStories")
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
            ("Stories", "Скачать сторис из Instagram", QtWidgets.QStyle.SP_FileDialogContentsView),
            ("Очередь профилей", "Пакетная выгрузка и управление списком", QtWidgets.QStyle.SP_FileDialogDetailedView),
            ("Reels", "Скачать Reels по ссылке", QtWidgets.QStyle.SP_MediaPlay),
        ]
        for index, (text, detail, icon_kind) in enumerate(
            [
                *nav_specs,
            ]
        ):
            button = self._build_nav_button(text, detail, icon_kind)
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
            "Настройки",
            "Обновления, среда и подключение к Instagram",
            QtWidgets.QStyle.SP_FileDialogContentsView,
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
        layout.setSpacing(12)

        layout.addWidget(
            self._hero(
                "Reels",
                "Скачать Reels по ссылке",
                supporting="Выгрузка Reels тут",
            )
        )

        content_row = QtWidgets.QHBoxLayout()
        content_row.setSpacing(12)

        left_column = QtWidgets.QVBoxLayout()
        left_column.setSpacing(12)

        input_card = self._card("Ссылки на Reels")
        input_layout = QtWidgets.QVBoxLayout(input_card)
        input_layout.setContentsMargins(16, 16, 16, 16)
        input_layout.setSpacing(12)
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
        self.reels_input.setMinimumHeight(160)
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
        buttons.setSpacing(10)
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
        right_column.setSpacing(12)
        right_column.addWidget(self._reels_status_card())
        right_column.addWidget(self._reels_downloads_card())
        right_column.addWidget(self._reels_logs_card(), 1)

        left_host = QtWidgets.QWidget()
        left_host.setLayout(left_column)
        right_host = QtWidgets.QWidget()
        right_host.setLayout(right_column)
        right_host.setMinimumWidth(360)
        right_host.setMaximumWidth(440)

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
        layout.setSpacing(12)

        layout.addWidget(
            self._hero(
                "Stories",
                "Скачать сторис из Instagram",
            )
        )

        content_row = QtWidgets.QHBoxLayout()
        content_row.setSpacing(12)

        left_column = QtWidgets.QVBoxLayout()
        left_column.setSpacing(12)
        left_column.addWidget(self._home2_composer_card())
        left_column.addWidget(self._home2_queue_card(), 1)

        right_column = QtWidgets.QVBoxLayout()
        right_column.setSpacing(12)
        right_column.addWidget(self._home2_status_card())
        right_column.addWidget(self._home2_result_card())
        right_column.addWidget(self._home2_recent_lists_card())
        right_column.addWidget(self._home2_activity_card(), 1)
        right_column.addStretch(1)

        left_host = QtWidgets.QWidget()
        left_host.setLayout(left_column)
        right_host = QtWidgets.QWidget()
        right_host.setLayout(right_column)
        right_host.setMinimumWidth(380)
        right_host.setMaximumWidth(460)

        content_row.addWidget(left_host, 3)
        content_row.addWidget(right_host, 2)
        layout.addLayout(content_row, 1)
        return page

    def _build_batch_page(self) -> QtWidgets.QWidget:
        page = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(12)

        layout.addWidget(
            self._hero(
                "Очередь профилей",
                "Добавь сразу несколько ссылок или usernames. Приложение обработает профили по очереди.",
                supporting="Управление списком профилей и массовой выгрузкой.",
            )
        )

        content_row = QtWidgets.QHBoxLayout()
        content_row.setSpacing(12)

        left_column = QtWidgets.QVBoxLayout()
        left_column.setSpacing(12)

        input_card = self._card("Добавить профили")
        input_layout = QtWidgets.QVBoxLayout(input_card)
        input_layout.setContentsMargins(16, 16, 16, 16)
        input_layout.setSpacing(12)
        input_layout.addWidget(self._section_caption("Добавить профили"))
        self.batch_input = QtWidgets.QPlainTextEdit()
        self.batch_input.setObjectName("profileEditor")
        self.batch_input.setPlaceholderText("Вставь по одной ссылке или username на строку.\nНапример:\nhttps://www.instagram.com/dian.vegas1/\nmonetentony")
        self.batch_input.setMinimumHeight(160)
        input_layout.addWidget(self.batch_input)

        input_buttons = QtWidgets.QHBoxLayout()
        input_buttons.setSpacing(10)
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
        queue_layout.setContentsMargins(16, 16, 16, 16)
        queue_layout.setSpacing(12)
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
        self.batch_table.verticalHeader().setDefaultSectionSize(34)
        self.batch_table.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.batch_table.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.batch_table.setAlternatingRowColors(True)
        self.batch_table.setMinimumHeight(220)
        queue_layout.addWidget(self.batch_table)

        queue_buttons = QtWidgets.QHBoxLayout()
        queue_buttons.setSpacing(10)
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
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)
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
        self.home2_batch_input.setMinimumHeight(160)
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
        row.setSpacing(10)
        add_button = QtWidgets.QPushButton("Добавить")
        add_button.setProperty("secondary", True)
        add_button.setIcon(self.style().standardIcon(QtWidgets.QStyle.SP_DialogOpenButton))
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
        actions.setSpacing(10)
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
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)
        layout.addWidget(self._section_caption("Очередь"))

        stats = QtWidgets.QHBoxLayout()
        stats.setSpacing(8)
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
        self.home2_batch_table.verticalHeader().setDefaultSectionSize(34)
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
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)
        layout.addWidget(self._section_caption("Недавние наборы"))
        self.home2_recent_lists_container = QtWidgets.QVBoxLayout()
        self.home2_recent_lists_container.setSpacing(10)
        layout.addLayout(self.home2_recent_lists_container)
        self.home2_recent_toggle = QtWidgets.QPushButton("Показать ещё ↓")
        self.home2_recent_toggle.setProperty("secondary", True)
        self.home2_recent_toggle.clicked.connect(self.toggle_home2_recent_lists)
        self.home2_recent_toggle.setVisible(False)
        layout.addWidget(self.home2_recent_toggle, 0, QtCore.Qt.AlignLeft)
        return card

    def _home2_status_card(self) -> QtWidgets.QWidget:
        card = self._card("Состояние")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)
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
        step_layout.setContentsMargins(12, 12, 12, 12)
        step_layout.setSpacing(4)
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
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)
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
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)
        layout.addWidget(self._section_caption("Журнал"))

        self.downloads_list = QtWidgets.QListWidget()
        self.downloads_list.setObjectName("downloadsList")
        self.downloads_list.itemDoubleClicked.connect(self.open_download_item)
        self.downloads_list.setSpacing(6)
        self.downloads_list.setUniformItemSizes(False)
        self.downloads_list.setMinimumHeight(120)
        layout.addWidget(self._group("Последние загрузки", self.downloads_list))

        self.home2_logs_text = QtWidgets.QPlainTextEdit()
        self.home2_logs_text.setObjectName("logsText")
        self.home2_logs_text.setReadOnly(True)
        self.home2_logs_text.setMinimumHeight(180)
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
        box_layout.setContentsMargins(12, 12, 12, 12)
        box_layout.setSpacing(8)
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
        layout.setContentsMargins(16, 14, 16, 14)
        layout.setSpacing(6)

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
        layout.setContentsMargins(16, 16, 16, 16)
        layout.addWidget(self._section_caption("Папка для сохранения"))
        line_edit = QtWidgets.QLineEdit(str(self.save_directory))
        line_edit.setObjectName("pathField")
        line_edit.setReadOnly(True)
        line_edit.setAlignment(QtCore.Qt.AlignRight | QtCore.Qt.AlignVCenter)
        line_edit.setCursorPosition(len(str(self.save_directory)))
        layout.addWidget(line_edit)

        button_row = QtWidgets.QHBoxLayout()
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
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)
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
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)
        layout.addWidget(self._section_caption("Последние загрузки"))
        self.reels_downloads_list = QtWidgets.QListWidget()
        self.reels_downloads_list.setObjectName("downloadsList")
        self.reels_downloads_list.itemDoubleClicked.connect(self.open_download_item)
        self.reels_downloads_list.setSpacing(6)
        self.reels_downloads_list.setMinimumHeight(150)
        layout.addWidget(self.reels_downloads_list)
        return card

    def _reels_logs_card(self) -> QtWidgets.QWidget:
        card = self._card("Логи")
        layout = QtWidgets.QVBoxLayout(card)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)
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
        self.reels_logs_text.setMinimumHeight(180)
        layout.addWidget(self.reels_logs_text)
        return card

    def _apply_styles(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow, QWidget#appRoot, QWidget#contentHost, QScrollArea, QScrollArea > QWidget > QWidget {
                background: #1c1c1c;
                color: #f3f3f3;
                font-size: 14px;
            }
            QFrame#sidebar {
                background: #161616;
                border-right: 1px solid rgba(255, 255, 255, 0.08);
            }
            QFrame#navBrand {
                background: rgba(255, 255, 255, 0.035);
                border: 1px solid rgba(255, 255, 255, 0.06);
                border-radius: 8px;
            }
            QLabel#sidebarTitle { font-family: "Segoe UI Variable"; font-size: 20px; font-weight: 600; color: #f8f8f8; }
            QLabel#sidebarSubtitle { font-family: "Segoe UI Variable"; font-size: 11px; font-weight: 600; color: #a0a0a0; text-transform: uppercase; letter-spacing: 0.08em; }
            QLabel#sidebarVersion {
                font-size: 11px;
                color: #bcbcbc;
                background: rgba(255,255,255,0.08);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 10px;
                padding: 3px 8px;
                margin-top: 6px;
            }
            QFrame#sidebarSeparator {
                min-height: 1px;
                max-height: 1px;
                border: none;
                background: rgba(255,255,255,0.08);
                margin: 4px 2px;
            }
            QPushButton[nav="true"] {
                text-align: left;
                padding: 14px 14px;
                border-radius: 8px;
                border: 1px solid transparent;
                background: transparent;
                color: #f2f2f2;
                font-family: "Segoe UI Variable";
                font-size: 14px;
                font-weight: 500;
                min-height: 58px;
            }
            QPushButton[nav="true"]:hover {
                background: rgba(255, 255, 255, 0.07);
                border-color: rgba(255, 255, 255, 0.10);
            }
            QPushButton[nav="true"]:checked {
                background: rgba(96, 205, 255, 0.18);
                border-color: rgba(96, 205, 255, 0.32);
            }
            QPushButton#applyUpdateButton {
                background: #0078d4;
                color: white;
                border: 1px solid #0078d4;
                border-radius: 4px;
                font-size: 14px;
                font-weight: 600;
                padding: 8px 12px;
                min-height: 32px;
            }
            QPushButton#applyUpdateButton:hover { background: #1287df; }
            QPushButton#applyUpdateButton:disabled {
                background: rgba(255,255,255,0.08);
                color: #8c8c8c;
                border-color: rgba(255,255,255,0.05);
            }
            QPushButton#queueActionButton {
                background: #0078d4;
                color: white;
                border: 1px solid #0078d4;
                border-radius: 4px;
                min-height: 36px;
            }
            QPushButton#queueActionButton:hover { background: #1287df; border-color: #1287df; }
            QPushButton#queueActionButton:disabled {
                background: rgba(255,255,255,0.10);
                color: rgba(255,255,255,0.45);
                border-color: rgba(255,255,255,0.05);
            }
            QPushButton {
                background: rgba(255,255,255,0.08);
                color: #f3f3f3;
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 4px;
                padding: 8px 12px;
                font-family: "Segoe UI Variable";
                font-weight: 500;
                min-height: 32px;
            }
            QPushButton:hover {
                background: rgba(255,255,255,0.12);
                border-color: rgba(255,255,255,0.12);
            }
            QPushButton:disabled {
                background: rgba(255,255,255,0.04);
                border-color: rgba(255,255,255,0.04);
                color: rgba(255,255,255,0.35);
            }
            QPushButton[secondary="true"] {
                background: rgba(255,255,255,0.06);
                border-color: rgba(255,255,255,0.08);
            }
            QPushButton[secondary="true"]:checked {
                background: rgba(0, 120, 212, 0.22);
                border-color: rgba(0, 120, 212, 0.34);
                color: #f5fbff;
            }
            QPushButton#subtleDangerButton:hover {
                background: rgba(255, 99, 99, 0.12);
                border-color: rgba(255, 99, 99, 0.22);
                color: #ffb0b0;
            }
            QFrame#cardSurface, QFrame#subCard, QFrame#stepCard, QGroupBox {
                background: rgba(255,255,255,0.048);
                border: 1px solid rgba(255,255,255,0.085);
                border-radius: 8px;
            }
            QFrame#inputShell {
                background: rgba(255,255,255,0.025);
                border-radius: 6px;
            }
            QGroupBox {
                margin-top: 8px;
                padding: 12px;
                font-weight: 600;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 4px;
                color: #d7d7d7;
            }
            QLabel#heroTitle { font-family: "Segoe UI Variable"; font-size: 20px; font-weight: 600; color: #f7f7f7; }
            QLabel#heroSubtitle { font-family: "Segoe UI Variable"; font-size: 14px; color: #c7c7c7; }
            QLabel#heroVersion {
                font-size: 12px;
                color: #b2b2b2;
                background: rgba(255,255,255,0.08);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 12px;
                padding: 4px 10px;
            }
            QLabel#sectionLabel {
                font-family: "Segoe UI Variable";
                font-size: 11px;
                font-weight: 600;
                color: #aaaaaa;
                text-transform: uppercase;
                letter-spacing: 0.08em;
            }
            QLabel#cardHint, QLabel#footnoteLabel, QLabel#inputCounter {
                font-size: 12px;
                color: #a6a6a6;
            }
            QLabel#statusBadge {
                background: rgba(255,255,255,0.08);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 12px;
                padding: 6px 12px;
                font-weight: 600;
                color: #dadada;
            }
            QLabel[statusTone="success"] {
                background: rgba(64, 196, 99, 0.16);
                border-color: rgba(64, 196, 99, 0.28);
                color: #82dc89;
            }
            QLabel[statusTone="error"] {
                background: rgba(255, 99, 99, 0.16);
                border-color: rgba(255, 99, 99, 0.28);
                color: #ff9f9f;
            }
            QLabel[statusTone="active"] {
                background: rgba(0, 120, 212, 0.18);
                border-color: rgba(0, 120, 212, 0.30);
                color: #91cbff;
            }
            QLabel[statusTone="idle"] {
                background: rgba(255,255,255,0.08);
                border-color: rgba(255,255,255,0.10);
                color: #d0d0d0;
            }
            QLabel[badge="true"] {
                background: rgba(255,255,255,0.08);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 12px;
                padding: 5px 10px;
                font-size: 12px;
                color: #cfcfcf;
            }
            QLineEdit, QPlainTextEdit, QListWidget, QTableWidget, QComboBox {
                background: rgba(255,255,255,0.05);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 4px;
                padding: 8px;
                color: #f2f2f2;
                selection-background-color: #0078d4;
            }
            QListWidget::item {
                padding: 8px;
                border-radius: 6px;
            }
            QListWidget::item:hover {
                background: rgba(255,255,255,0.06);
            }
            QListWidget::item:selected {
                background: rgba(0, 120, 212, 0.26);
            }
            QTableWidget {
                alternate-background-color: rgba(255,255,255,0.03);
            }
            QTableWidget::item {
                padding: 6px;
            }
            QTableCornerButton::section {
                background: rgba(255,255,255,0.06);
                border: none;
                border-bottom: 1px solid rgba(255,255,255,0.08);
                border-right: 1px solid rgba(255,255,255,0.08);
            }
            QPlainTextEdit#profileEditor, QPlainTextEdit#logsText {
                font-family: "Cascadia Mono";
                font-size: 13px;
            }
            QLineEdit#pathField {
                font-family: "Cascadia Mono";
            }
            QToolButton#inlineClearButton {
                background: rgba(255,255,255,0.08);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 10px;
                padding: 2px;
                margin: 8px;
            }
            QToolButton#inlineClearButton:hover {
                background: rgba(255,255,255,0.14);
            }
            QToolButton#inlineRemoveButton {
                color: #bcbcbc;
                background: rgba(255,255,255,0.05);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 9px;
                padding: 2px 4px;
            }
            QToolButton#inlineRemoveButton:hover {
                color: #ffffff;
                background: rgba(255,255,255,0.12);
            }
            QFrame#metricTile {
                background: rgba(255,255,255,0.05);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 8px;
            }
            QLabel#metricValue {
                font-size: 24px;
                font-weight: 600;
                color: #f6f6f6;
            }
            QLabel#metricTitle {
                font-size: 12px;
                color: #b1b1b1;
            }
            QLabel#metricDot {
                font-size: 12px;
            }
            QHeaderView::section {
                background: rgba(255,255,255,0.06);
                border: none;
                border-bottom: 1px solid rgba(255,255,255,0.08);
                padding: 8px;
                font-weight: 600;
                color: #e0e0e0;
            }
            QTableWidget#queueTable {
                gridline-color: rgba(255,255,255,0.08);
            }
            QProgressBar#queueProgressBar {
                background: rgba(255,255,255,0.05);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 4px;
                min-height: 8px;
                max-height: 8px;
            }
            QProgressBar#queueProgressBar::chunk {
                border-radius: 4px;
                background: #0078d4;
            }
            QScrollBar:vertical {
                background: transparent;
                width: 12px;
                margin: 2px 0;
            }
            QScrollBar::handle:vertical {
                background: rgba(255,255,255,0.16);
                min-height: 28px;
                border-radius: 6px;
            }
            QScrollBar::handle:vertical:hover {
                background: rgba(255,255,255,0.24);
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical,
            QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical,
            QScrollBar:horizontal, QScrollBar::handle:horizontal,
            QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal,
            QScrollBar::add-page:horizontal, QScrollBar::sub-page:horizontal {
                background: transparent;
                border: none;
                width: 0px;
                height: 0px;
            }
            """
        )

    def _card(self, title: str) -> QtWidgets.QFrame:
        del title
        card = QtWidgets.QFrame()
        card.setObjectName("cardSurface")
        return card

    def _section_caption(self, text: str) -> QtWidgets.QLabel:
        label = QtWidgets.QLabel(text)
        label.setObjectName("sectionLabel")
        return label

    def _build_nav_button(self, text: str, detail: str, icon_kind: QtWidgets.QStyle.StandardPixmap) -> QtWidgets.QPushButton:
        button = QtWidgets.QPushButton(f"{text}\n{detail}")
        button.setCheckable(True)
        button.setProperty("nav", True)
        button.setIcon(self.style().standardIcon(icon_kind))
        button.setIconSize(QtCore.QSize(18, 18))
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
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(6)

        title_row = QtWidgets.QHBoxLayout()
        title_row.setContentsMargins(0, 0, 0, 0)
        title_row.setSpacing(6)
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
        layout.setSpacing(8)
        layout.addWidget(self._section_caption(title))

        row = QtWidgets.QHBoxLayout()
        row.setSpacing(8)
        combo = QtWidgets.QComboBox()
        combo.hide()
        buttons: list[QtWidgets.QPushButton] = []
        for index, (button_text, _, value) in enumerate(options):
            combo.addItem(button_text, value)
            button = QtWidgets.QPushButton(button_text)
            button.setCheckable(True)
            button.setProperty("secondary", True)
            button.clicked.connect(lambda checked=False, i=index, target=combo: target.setCurrentIndex(i))
            row.addWidget(button, 1)
            buttons.append(button)
        combo.currentIndexChanged.connect(change_handler)
        layout.addLayout(row)
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
        lines = [line.strip() for line in self.home2_batch_input.toPlainText().splitlines() if line.strip()]
        count = len(lines)
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
