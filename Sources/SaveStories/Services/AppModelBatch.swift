import AppKit
import Foundation

extension AppModel {
    func addBatchProfiles() {
        let parsed = parsedBatchLinks(from: batchInput)
        guard !parsed.isEmpty else {
            appendLog("Для списка не найдено ни одной ссылки на профиль.")
            return
        }

        let existing = Set(batchQueue.map { normalizedProfileLink($0.url) })
        var seen = existing
        let newItems = parsed
            .map(normalizedProfileLink)
            .filter { candidate in
                guard !seen.contains(candidate) else { return false }
                seen.insert(candidate)
                return true
            }
            .map { BatchProfileItem(url: $0) }

        guard !newItems.isEmpty else {
            appendLog("Все ссылки из вставки уже есть в очереди.")
            batchInput = ""
            return
        }

        batchQueue.append(contentsOf: newItems)
        batchInput = ""
        appendLog("В очередь добавлено профилей: \(newItems.count).")
    }

    func removeBatchProfile(id: UUID) {
        guard !isBusy else { return }
        batchQueue.removeAll { $0.id == id }
    }

    func clearBatchQueue() {
        guard !isBusy else { return }
        batchQueue.removeAll()
        resetBatchProgress()
        appendLog("Очередь пакетной выгрузки очищена.")
    }

    func rememberCurrentBatchList() {
        let urls = batchQueue.map(\.url)
        guard !urls.isEmpty else {
            appendLog("Нечего запоминать: очередь профилей пока пуста.")
            return
        }

        let title = suggestedRecentListTitle(for: urls)
        storeRecentBatchList(title: title, urls: urls)
        appendLog("Список профилей сохранён в недавние: \(title).")
    }

    func applyRecentBatchList(_ list: RecentBatchList) {
        let existing = Set(batchQueue.map { normalizedProfileLink($0.url) })
        var seen = existing
        let newItems = list.urls
            .map(normalizedProfileLink)
            .filter { candidate in
                guard !seen.contains(candidate) else { return false }
                seen.insert(candidate)
                return true
            }
            .map { BatchProfileItem(url: $0, message: "Добавлено из недавнего списка.") }

        guard !newItems.isEmpty else {
            appendLog("Все профили из списка «\(list.title)» уже есть в очереди.")
            return
        }

        batchQueue.append(contentsOf: newItems)
        appendLog("Из списка «\(list.title)» добавлено профилей: \(newItems.count).")
    }

    func replaceQueueWithRecentBatchList(_ list: RecentBatchList) {
        guard !isBusy else { return }
        batchQueue = list.urls.map { BatchProfileItem(url: normalizedProfileLink($0), message: "Загружено из недавнего списка.") }
        resetBatchProgress()
        appendLog("Очередь заменена списком «\(list.title)».")
    }

    func removeRecentBatchList(id: UUID) {
        recentBatchLists.removeAll { $0.id == id }
        persistRecentBatchLists()
        appendLog("Недавний список удалён.")
    }

    func runBatchDownloads() async {
        let pendingItems = batchQueue.filter { $0.status == .pending || $0.status == .failed }
        guard !pendingItems.isEmpty else {
            appendLog("В очереди нет ссылок для пакетной выгрузки.")
            return
        }

        playActionSound()

        await perform("Пакетная выгрузка активных stories") {
            self.storeRecentBatchList(
                title: self.suggestedRecentListTitle(for: pendingItems.map(\.url)),
                urls: pendingItems.map(\.url)
            )
            self.batchIsRunning = true
            self.batchStopRequested = false
            self.batchCurrentIndex = 1
            self.batchTotalCount = pendingItems.count
            self.batchRemainingCount = max(pendingItems.count - 1, 0)
            self.batchCurrentURL = "Пакетная выгрузка выполняется в одном окне браузера."
            self.currentStepLabel = "Подготавливаю общую очередь профилей."

            for item in pendingItems {
                self.updateBatchProfile(id: item.id, status: .running, message: "Ожидает обработки в общем окне браузера.")
            }

            self.statusTitle = "Пакетная выгрузка"
            self.statusDetail = "Вся очередь обрабатывается в одном окне браузера."

            let response = await self.worker.run(
                WorkerRequest(
                    command: "download_profile_batch",
                    url: nil,
                    urls: pendingItems.map { self.normalizedProfileLink($0.url) },
                    outputDirectory: self.saveDirectory.path,
                    headless: self.downloadMode.usesHeadless,
                    mediaFilter: self.mediaSelectionMode.rawValue
                ),
                onProgress: { [weak self] progressLine in
                    Task { @MainActor in
                        self?.handleWorkerProgress(progressLine)
                    }
                }
            )

            if response.status == "cancelled" {
                for item in pendingItems where self.batchQueue.contains(where: { $0.id == item.id && $0.status == .running }) {
                    self.updateBatchProfile(id: item.id, status: .stopped, message: "Пакетная выгрузка остановлена пользователем.")
                }
                self.append(response)
                self.statusTitle = "Остановлено"
                self.statusDetail = "Пакетная выгрузка остановлена пользователем."
                self.lastResult = self.statusDetail
                self.currentStepLabel = "Пакетная выгрузка остановлена."
                self.batchRemainingCount = pendingItems.count
                self.batchCurrentIndex = 0
                self.batchCurrentURL = ""
                self.batchIsRunning = false
                self.batchStopRequested = false
                return
            }

            self.applyBatchResults(response, pendingItems: pendingItems)
            self.append(response)

            let processedCount = Int(response.data["processedCount"] ?? "") ?? pendingItems.count
            let failedCount = pendingItems.filter { item in
                self.batchQueue.first(where: { $0.id == item.id })?.status == .failed
            }.count

            self.statusTitle = failedCount == 0 ? "Готово" : "Завершено с ошибками"
            self.statusDetail = "Обработано \(processedCount) профилей. Сохранено файлов: \(self.savedStoriesCount)."
            self.lastResult = self.statusDetail
            self.currentStepLabel = failedCount == 0 ? "Очередь обработана." : "Очередь завершилась с ошибками."
            if self.savedStoriesCount > 0 {
                self.triggerCelebration()
            }
            self.batchRemainingCount = 0
            self.batchCurrentURL = ""
            self.batchCurrentIndex = 0
            self.batchIsRunning = false
            self.batchStopRequested = false
            self.prepareEmptyStoryFolderCleanupPrompt()
        }
    }

    func stopBatchDownloads() {
        guard batchIsRunning else { return }
        batchStopRequested = true
        worker.stopCurrentProcess()
        statusTitle = "Остановка"
        statusDetail = "Останавливаю текущую выгрузку профиля..."
        appendLog("Запрошена остановка пакетной выгрузки.")
    }

    func copyLogs() {
        let orderedLogs = logs.reversed().joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(orderedLogs, forType: .string)
        appendLog("Логи скопированы в буфер обмена.")
    }

    func openSaveDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([saveDirectory])
    }

    func revealDownloadedItem(at path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openRuntimeDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.applicationSupport])
    }

    func dismissEmptyFolderCleanupPrompt() {
        pendingEmptyStoryFolders = []
        showEmptyFolderCleanupPrompt = false
    }

    func removePendingEmptyStoryFolders() {
        let folders = pendingEmptyStoryFolders
        pendingEmptyStoryFolders = []
        showEmptyFolderCleanupPrompt = false

        guard !folders.isEmpty else {
            emptyFolderCleanupReport = EmptyFolderCleanupReport(removedCount: 0, folderNames: [])
            return
        }

        let manager = FileManager.default
        var removedNames: [String] = []
        for folder in folders {
            do {
                try manager.removeItem(at: folder)
                removedNames.append(folder.lastPathComponent)
            } catch {
                appendLog("Не удалось удалить пустую папку \(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !removedNames.isEmpty {
            appendLog("Удалены пустые папки после выгрузки stories: \(removedNames.joined(separator: ", ")).")
        }
        emptyFolderCleanupReport = EmptyFolderCleanupReport(removedCount: removedNames.count, folderNames: removedNames)
    }

    func parsedBatchLinks(from input: String) -> [String] {
        input
            .split(whereSeparator: \.isNewline)
            .flatMap { chunk in
                chunk.split(separator: ",")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func normalizedProfileLink(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.contains("instagram.com") {
            return trimmed
        }

        let username = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
        return "https://www.instagram.com/\(username)/"
    }

    func updateBatchProfile(id: UUID, status: BatchProfileItem.Status, message: String) {
        guard let index = batchQueue.firstIndex(where: { $0.id == id }) else { return }
        batchQueue[index].status = status
        batchQueue[index].message = message
    }

    func prepareEmptyStoryFolderCleanupPrompt() {
        let emptyFolders = emptyStoryFolders(in: saveDirectory)
        guard !emptyFolders.isEmpty else { return }
        pendingEmptyStoryFolders = emptyFolders
        showEmptyFolderCleanupPrompt = true
        appendLog("Найдены пустые папки после выгрузки stories: \(emptyFolders.count).")
    }

    func emptyStoryFolders(in root: URL) -> [URL] {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.filter { candidate in
            guard (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            return isEffectivelyEmptyDirectory(candidate)
        }
    }

    private func isEffectivelyEmptyDirectory(_ directory: URL) -> Bool {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return false
        }

        for case let item as URL in enumerator {
            guard item != directory else { continue }
            return false
        }
        return true
    }

    func applyBatchResults(_ response: WorkerResponse, pendingItems: [BatchProfileItem]) {
        let found = Int(response.data["foundCount"] ?? "") ?? response.items.count
        let saved = Int(response.data["savedCount"] ?? "") ?? response.items.count
        foundStoriesCount = found
        savedStoriesCount = saved

        guard let raw = response.data["batchResults"],
              let data = raw.data(using: .utf8),
              let results = try? JSONDecoder().decode([BatchWorkerResult].self, from: data)
        else {
            for item in pendingItems {
                updateBatchProfile(
                    id: item.id,
                    status: response.ok ? .completed : .failed,
                    message: response.message
                )
            }
            return
        }

        let resultMap = Dictionary(uniqueKeysWithValues: results.map { (normalizedProfileLink($0.url), $0) })
        for item in pendingItems {
            let normalized = normalizedProfileLink(item.url)
            guard let result = resultMap[normalized] else {
                updateBatchProfile(id: item.id, status: .failed, message: "Для профиля нет результата пакетной выгрузки.")
                continue
            }
            let status: BatchProfileItem.Status
            switch result.status {
            case "completed":
                status = .completed
            case "stopped":
                status = .stopped
            default:
                status = .failed
            }
            updateBatchProfile(id: item.id, status: status, message: result.message)
        }
    }

    func resetBatchProgress() {
        batchIsRunning = false
        batchStopRequested = false
        batchCurrentIndex = 0
        batchTotalCount = 0
        batchRemainingCount = 0
        batchCurrentURL = ""
    }

    func suggestedRecentListTitle(for urls: [String]) -> String {
        let normalized = urls.map(normalizedProfileLink)
        guard let first = normalized.first else { return "Недавний список" }
        let username = first
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .last
            .map(String.init) ?? "profiles"
        return normalized.count == 1 ? username : "\(username) +\(normalized.count - 1)"
    }

    func loadRecentBatchLists() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentBatchListsKey),
              let decoded = try? JSONDecoder().decode([RecentBatchList].self, from: data) else {
            recentBatchLists = []
            return
        }
        recentBatchLists = decoded
    }

    func persistRecentBatchLists() {
        guard let data = try? JSONEncoder().encode(recentBatchLists) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentBatchListsKey)
    }

    func storeRecentBatchList(title: String, urls: [String]) {
        let normalizedURLs = urls.map(normalizedProfileLink)
        guard !normalizedURLs.isEmpty else { return }

        recentBatchLists.removeAll { $0.urls.map(normalizedProfileLink) == normalizedURLs }
        recentBatchLists.insert(
            RecentBatchList(title: title, urls: normalizedURLs),
            at: 0
        )
        if recentBatchLists.count > 8 {
            recentBatchLists = Array(recentBatchLists.prefix(8))
        }
        persistRecentBatchLists()
    }
}
