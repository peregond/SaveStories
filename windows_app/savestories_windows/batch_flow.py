from __future__ import annotations

import json

from PySide6 import QtCore, QtWidgets

from .models import BatchEntry, WorkerRequest, WorkerResponse
from .ui_support import batch_status_title, normalize_profile_link, parse_batch_links, suggested_recent_list_title


class MainWindowBatchFlowMixin:
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
        if hasattr(self, "home2_run_button"):
            self.home2_run_button.setEnabled(False)
        if hasattr(self, "home2_stop_button"):
            self.home2_stop_button.setEnabled(True)
        total = len(self.batch_pending_indices)
        remaining = max(total - 1, 0)
        self.batch_progress_label.setText(
            f"Сейчас 1 из {total}, осталось {remaining}. Очередь выполняется в одном окне браузера."
        )
        if hasattr(self, "home2_progress_label"):
            self.home2_progress_label.setText(
                f"Сейчас 1 из {total}, осталось {remaining}. Очередь выполняется в одном окне браузера."
            )
        self.current_step_label = "Подготавливаю общую очередь профилей."
        self.refresh_home2_status_strip()

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
                mediaFilter=self.current_media_filter(),
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
        processed = sum(
            1
            for index in self.batch_pending_indices
            if self.batch_entries[index].status in {"completed", "failed", "stopped"}
        )
        total = len(self.batch_pending_indices)
        failed = sum(1 for index in self.batch_pending_indices if self.batch_entries[index].status == "failed")
        completed = sum(1 for index in self.batch_pending_indices if self.batch_entries[index].status == "completed")
        if self.batch_stop_requested:
            self.set_status("Остановлено", f"Пакетная выгрузка остановлена. Обработано {processed} из {total}.")
        else:
            if failed > 0 and completed == 0:
                self.set_status("Ошибка", f"Пакетная выгрузка завершилась ошибками. Обработано {processed} из {total}.")
            elif failed > 0:
                self.set_status("Завершено с ошибками", f"Пакетная выгрузка завершилась с ошибками. Обработано {processed} из {total}.")
            else:
                self.set_status("Готово", f"Пакетная выгрузка завершена. Сохранено файлов: {self.batch_saved_total}.")
            if self.batch_saved_total > 0 and completed > 0:
                self.trigger_celebration()
        self.batch_running = False
        self.batch_stop_requested = False
        self.batch_pending_indices = []
        self.batch_cursor = 0
        self.batch_progress_label.setText("Очередь готова.")
        self.batch_run_button.setEnabled(True)
        self.batch_stop_button.setEnabled(False)
        if hasattr(self, "home2_progress_label"):
            self.home2_progress_label.setText("Очередь готова.")
        if hasattr(self, "home2_run_button"):
            self.home2_run_button.setEnabled(True)
        if hasattr(self, "home2_stop_button"):
            self.home2_stop_button.setEnabled(False)
        self.current_step_label = "Очередь обработана."
        self.refresh_home2_status_strip()

    def stop_batch(self) -> None:
        if not self.batch_running:
            return
        self.batch_stop_requested = True
        self.worker.stop_current_process()
        self.set_status("Остановка", "Останавливаю текущую выгрузку...")
        self.current_step_label = "Останавливаю пакетную выгрузку."
        self.refresh_home2_status_strip()
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

    def add_batch_profiles_from_home2(self) -> None:
        new_links = parse_batch_links(self.home2_batch_input.toPlainText())
        if not new_links:
            self.append_log("Для списка не найдено ни одной ссылки на профиль.")
            return

        existing = {item.url for item in self.batch_entries}
        added = 0
        for link in new_links:
            if link in existing:
                continue
            existing.add(link)
            self.batch_entries.append(BatchEntry(url=link))
            added += 1

        self.home2_batch_input.clear()
        self.refresh_batch_table()
        self.batch_progress_label.setText(f"В очереди профилей: {len(self.batch_entries)}.")
        self.append_log(f"В очередь добавлено профилей: {added}.")

    def clear_home2_input(self) -> None:
        self.home2_batch_input.clear()

    def remember_current_batch_list(self) -> None:
        urls = [entry.url for entry in self.batch_entries]
        if not urls:
            self.append_log("Нечего запоминать: очередь профилей пока пуста.")
            return
        title = suggested_recent_list_title(urls)
        normalized_urls = [normalize_profile_link(url) for url in urls]
        self.recent_lists = [item for item in self.recent_lists if item.get("urls") != normalized_urls]
        self.recent_lists.insert(0, {"title": title, "urls": normalized_urls})
        self.recent_lists = self.recent_lists[:8]
        self.persist_recent_lists()
        self.refresh_recent_lists_ui()
        self.append_log(f"Список профилей сохранён в недавние: {title}.")

    def apply_recent_list(self, urls: list[str]) -> None:
        existing = {item.url for item in self.batch_entries}
        added = 0
        for raw in urls:
            link = normalize_profile_link(raw)
            if link in existing:
                continue
            existing.add(link)
            self.batch_entries.append(BatchEntry(url=link, message="Добавлено из недавнего списка."))
            added += 1
        self.refresh_batch_table()
        self.append_log(f"Из недавнего списка добавлено профилей: {added}.")

    def replace_with_recent_list(self, urls: list[str]) -> None:
        if self.batch_running:
            return
        self.batch_entries = [BatchEntry(url=normalize_profile_link(url), message="Загружено из недавнего списка.") for url in urls]
        self.refresh_batch_table()
        self.batch_progress_label.setText(f"В очереди профилей: {len(self.batch_entries)}.")
        self.append_log("Очередь заменена недавним списком.")

    def remove_recent_list(self, index: int) -> None:
        if index < 0 or index >= len(self.recent_lists):
            return
        self.recent_lists.pop(index)
        self.persist_recent_lists()
        self.refresh_recent_lists_ui()
        self.append_log("Недавний список удалён.")

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
        if hasattr(self, "home2_batch_table"):
            self.home2_batch_table.setRowCount(len(self.batch_entries))
            for row, entry in enumerate(self.batch_entries):
                self.home2_batch_table.setItem(row, 0, QtWidgets.QTableWidgetItem(entry.url))
                self.home2_batch_table.setItem(row, 1, QtWidgets.QTableWidgetItem(batch_status_title(entry.status)))
                self.home2_batch_table.setItem(row, 2, QtWidgets.QTableWidgetItem(entry.message))
        if hasattr(self, "home2_run_button"):
            self.home2_run_button.setEnabled(bool(self.batch_entries) and not self.current_task)
        if hasattr(self, "home2_clear_button"):
            self.home2_clear_button.setEnabled(bool(self.batch_entries) and not self.batch_running)
        self.refresh_home2_status_strip()

    def load_recent_lists(self) -> list[dict[str, object]]:
        raw = str(self.settings_store.value("recent_batch_lists", "") or "").strip()
        if not raw:
            return []
        try:
            payload = json.loads(raw)
        except Exception:
            return []
        if not isinstance(payload, list):
            return []
        result: list[dict[str, object]] = []
        for item in payload:
            if not isinstance(item, dict):
                continue
            title = str(item.get("title") or "Недавний список").strip()
            urls = item.get("urls") or []
            if not isinstance(urls, list):
                continue
            normalized_urls = [normalize_profile_link(str(url)) for url in urls if str(url).strip()]
            if normalized_urls:
                result.append({"title": title, "urls": normalized_urls})
        return result[:8]

    def persist_recent_lists(self) -> None:
        self.settings_store.setValue("recent_batch_lists", json.dumps(self.recent_lists, ensure_ascii=False))

    def refresh_recent_lists_ui(self) -> None:
        if not hasattr(self, "home2_recent_lists_container"):
            return

        while self.home2_recent_lists_container.count():
            item = self.home2_recent_lists_container.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()

        if not self.recent_lists:
            label = QtWidgets.QLabel("Здесь появятся сохранённые наборы профилей.")
            label.setWordWrap(True)
            label.setObjectName("cardHint")
            label.setAlignment(QtCore.Qt.AlignHCenter)
            self.home2_recent_lists_container.addWidget(label)
            self.home2_recent_count.setText("Недавних наборов: 0")
            if hasattr(self, "home2_recent_toggle"):
                self.home2_recent_toggle.setVisible(False)
            return

        show_all = self.home2_recent_expanded
        visible_items = self.recent_lists if show_all else self.recent_lists[:3]
        for visible_index, item in enumerate(visible_items):
            title = str(item.get("title") or "Недавний список")
            urls = [str(url) for url in item.get("urls", [])]
            original_index = self.recent_lists.index(item)

            card = QtWidgets.QFrame()
            card.setObjectName("subCard")
            layout = QtWidgets.QVBoxLayout(card)
            layout.setContentsMargins(12, 12, 12, 12)
            layout.setSpacing(8)

            header = QtWidgets.QHBoxLayout()
            header.setContentsMargins(0, 0, 0, 0)
            header.setSpacing(8)
            title_label = QtWidgets.QLabel(title)
            title_label.setStyleSheet("font-weight: 600;")
            summary = QtWidgets.QLabel(f"{len(urls)} профилей")
            summary.setObjectName("cardHint")
            remove_button = QtWidgets.QToolButton()
            remove_button.setText("✕")
            remove_button.setObjectName("inlineRemoveButton")
            remove_button.setAutoRaise(True)
            remove_button.clicked.connect(lambda checked=False, item_index=original_index: self.remove_recent_list(item_index))
            header.addWidget(title_label, 1)
            header.addWidget(summary, 0, QtCore.Qt.AlignLeft)
            header.addWidget(remove_button, 0, QtCore.Qt.AlignRight)

            preview = QtWidgets.QLabel("\n".join(urls[:2]))
            preview.setWordWrap(True)
            preview.setStyleSheet("font-family: 'Cascadia Mono';")
            layout.addLayout(header)
            layout.addWidget(preview)

            row = QtWidgets.QHBoxLayout()
            row.setSpacing(8)
            add_button = QtWidgets.QPushButton("Добавить в очередь")
            add_button.setProperty("secondary", True)
            add_button.clicked.connect(lambda checked=False, batch_urls=urls: self.apply_recent_list(batch_urls))
            replace_button = QtWidgets.QPushButton("Заменить очередь")
            replace_button.setProperty("secondary", True)
            replace_button.clicked.connect(lambda checked=False, batch_urls=urls: self.replace_with_recent_list(batch_urls))
            row.addWidget(add_button, 1)
            row.addWidget(replace_button, 1)
            layout.addLayout(row)
            self.home2_recent_lists_container.addWidget(card)

        self.home2_recent_lists_container.addStretch(1)
        self.home2_recent_count.setText(f"Недавних наборов: {len(self.recent_lists)}")
        if hasattr(self, "home2_recent_toggle"):
            has_more = len(self.recent_lists) > 3
            self.home2_recent_toggle.setVisible(has_more)
            self.home2_recent_toggle.setText("Свернуть ↑" if show_all else "Показать ещё ↓")

    def toggle_home2_recent_lists(self) -> None:
        self.home2_recent_expanded = not self.home2_recent_expanded
        self.refresh_recent_lists_ui()
