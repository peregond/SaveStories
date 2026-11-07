import AppKit
import Foundation

extension AppModel {
    func addBatchProfiles() {
        guard !isBusy else { return }
        let normalized = normalizedBatchLinks(from: batchInput)
        guard !normalized.isEmpty else {
            appendLog(L("Для списка не найдено ни одной ссылки на профиль."))
            return
        }

        let existing = Set(batchQueue.map { normalizedProfileLink($0.url).lowercased() })
        var seen = existing
        let newItems = normalized
            .filter { candidate in
                seen.insert(candidate.lowercased()).inserted
            }
            .map { BatchProfileItem(url: $0) }

        guard !newItems.isEmpty else {
            appendLog(L("Все ссылки из вставки уже есть в очереди."))
            batchInput = ""
            return
        }

        batchQueue.append(contentsOf: newItems)
        batchInput = ""
        appendLog(L("В очередь добавлено профилей: {0}.", newItems.count))
    }

    func removeBatchProfile(id: UUID) {
        guard !isBusy else { return }
        batchQueue.removeAll { $0.id == id }
    }

    func clearBatchQueue() {
        guard !isBusy else { return }
        batchQueue.removeAll()
        resetBatchProgress()
        appendLog(L("Очередь пакетной выгрузки очищена."))
    }

    func rememberCurrentBatchList() {
        let urls = batchQueue.map(\.url)
        guard !urls.isEmpty else {
            appendLog(L("Нечего запоминать: очередь профилей пока пуста."))
            return
        }

        let title = suggestedRecentListTitle(for: urls)
        storeRecentBatchList(title: title, urls: urls)
        appendLog(L("Список профилей сохранён в недавние: {0}.", title))
    }

    func applyRecentBatchList(_ list: RecentBatchList) {
        guard !isBusy else { return }
        let existing = Set(batchQueue.map { normalizedProfileLink($0.url).lowercased() })
        var seen = existing
        let newItems = list.urls
            .map(normalizedProfileLink)
            .filter { !$0.isEmpty }
            .filter { candidate in
                seen.insert(candidate.lowercased()).inserted
            }
            .map { BatchProfileItem(url: $0, message: L("Добавлено из недавнего списка.")) }

        guard !newItems.isEmpty else {
            appendLog(L("Все профили из списка «{0}» уже есть в очереди.", list.title))
            return
        }

        batchQueue.append(contentsOf: newItems)
        appendLog(L("Из списка «{0}» добавлено профилей: {1}.", list.title, newItems.count))
    }

    func replaceQueueWithRecentBatchList(_ list: RecentBatchList) {
        guard !isBusy else { return }
        var seen = Set<String>()
        batchQueue = list.urls
            .map(normalizedProfileLink)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .map { BatchProfileItem(url: $0, message: L("Загружено из недавнего списка.")) }
        resetBatchProgress()
        appendLog(L("Очередь заменена списком «{0}».", list.title))
    }

    func removeRecentBatchList(id: UUID) {
        recentBatchLists.removeAll { $0.id == id }
        persistRecentBatchLists()
        appendLog(L("Недавний список удалён."))
    }

    @discardableResult
    func refreshNotionInfluencerQueue(replaceQueue: Bool = true, force: Bool = false) async -> Bool {
        guard !isDesignPreview, !isBusy, !isRefreshingNotionInfluencers else { return false }

        if !force, wasNotionSourceRefreshedToday(key: Self.notionInfluencerLastRefreshAtKey) {
            let cachedProfiles = UserDefaults.standard.stringArray(forKey: Self.notionInfluencerCachedProfilesKey) ?? []
            guard !cachedProfiles.isEmpty else {
                notionInfluencerSourceSummary = L("Notion уже обновлялся сегодня, но сохранённый список пуст.")
                appendLog(L("Повторная загрузка Notion пропущена: сегодня уже обновляли, сохранённый список пуст."))
                return false
            }

            let appliedCount = applyNotionInfluencerProfiles(cachedProfiles, replaceQueue: replaceQueue)
            notionInfluencerSourceSummary = L("Notion уже обновлялся сегодня: использую сохранённый список ({0} профилей).", cachedProfiles.count)
            currentStepLabel = L("Использую сохранённый Notion-список.")
            appendLog(L("Повторная загрузка Notion пропущена: применён сохранённый список, профилей: {0}.", appliedCount))
            return true
        }

        isRefreshingNotionInfluencers = true
        notionInfluencerSourceSummary = L("Загружаю свежий список из Notion...")
        currentStepLabel = L("Получаю список инфлюенсеров из Notion.")
        defer { isRefreshingNotionInfluencers = false }

        do {
            let profiles = try await NotionInfluencerSource().fetchProfiles()
            guard !profiles.isEmpty else {
                notionInfluencerSourceSummary = L("В Notion не найдено профилей.")
                appendLog(L("В Notion-списке не найдено профилей."))
                return false
            }

            let appliedCount = applyNotionInfluencerProfiles(profiles, replaceQueue: replaceQueue)
            if replaceQueue {
                appendLog(L("Очередь заменена свежим Notion-списком: {0} профилей.", profiles.count))
            } else {
                appendLog(L("Из Notion-списка добавлено новых профилей: {0}.", appliedCount))
            }

            UserDefaults.standard.set(profiles, forKey: Self.notionInfluencerCachedProfilesKey)
            markNotionSourceRefreshed(key: Self.notionInfluencerLastRefreshAtKey)
            let timestamp = Date().formatted(date: .omitted, time: .shortened)
            notionInfluencerSourceSummary = L("Notion обновлён в {0}: {1} профилей.", timestamp, profiles.count)
            currentStepLabel = L("Список Notion загружен.")
            return true
        } catch {
            notionInfluencerSourceSummary = L("Не удалось обновить Notion: {0}", error.localizedDescription)
            statusTitle = L("Ошибка Notion")
            statusDetail = notionInfluencerSourceSummary
            lastResult = notionInfluencerSourceSummary
            currentStepLabel = L("Notion-список не загружен.")
            appendLog(L("Не удалось загрузить Notion-список: {0}", error.localizedDescription))
            return false
        }
    }

    private func applyNotionInfluencerProfiles(_ profiles: [String], replaceQueue: Bool) -> Int {
        if replaceQueue {
            var seen = Set<String>()
            batchQueue = profiles
                .map(normalizedProfileLink)
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
                .map { BatchProfileItem(url: $0, message: L("Загружено из Notion-списка.")) }
            resetBatchProgress()
            return batchQueue.count
        }

        let existing = Set(batchQueue.map { normalizedProfileLink($0.url).lowercased() })
        var seen = existing
        let newItems = profiles
            .map(normalizedProfileLink)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .map { BatchProfileItem(url: $0, message: L("Добавлено из Notion-списка.")) }

        batchQueue.append(contentsOf: newItems)
        return newItems.count
    }

    /// An explicit pasted selection takes precedence over the automatic Notion source.
    func downloadStoriesFromInput() async {
        let hasManualInput = !normalizedBatchLinks(from: batchInput).isEmpty
        if hasManualInput { addBatchProfiles() }
        await runBatchDownloads(refreshNotionQueue: !hasManualInput)
    }

    func runBatchDownloads(refreshNotionQueue: Bool = true) async {
        guard !isBusy else { return }
        if refreshNotionQueue && notionInfluencerSourceEnabled {
            let refreshed = await refreshNotionInfluencerQueue(replaceQueue: true)
            guard refreshed else { return }
        }

        let pendingItems = batchQueue.filter { $0.status == .pending || $0.status == .failed }
        guard !pendingItems.isEmpty else {
            appendLog(L("В очереди нет ссылок для пакетной выгрузки."))
            return
        }

        playActionSound()

        await perform(L("Пакетная выгрузка активных stories")) {
            self.storeRecentBatchList(
                title: self.suggestedRecentListTitle(for: pendingItems.map(\.url)),
                urls: pendingItems.map(\.url)
            )
            self.batchIsRunning = true
            self.batchStopRequested = false
            self.batchProgressStartedURLs.removeAll()
            self.batchProgressCompletedURLs.removeAll()
            self.batchCurrentIndex = 0
            self.batchTotalCount = pendingItems.count
            self.batchRemainingCount = pendingItems.count
            self.batchCurrentURL = L("Пакетная выгрузка выполняется в одном окне браузера.")
            self.currentStepLabel = L("Подготавливаю общую очередь профилей.")

            for item in pendingItems {
                self.updateBatchProfile(id: item.id, status: .running, message: L("Ожидает обработки в общем окне браузера."))
            }

            self.statusTitle = L("Пакетная выгрузка")
            self.statusDetail = L("Вся очередь обрабатывается в одном окне браузера.")

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
                    self.updateBatchProfile(id: item.id, status: .stopped, message: L("Пакетная выгрузка остановлена пользователем."))
                }
                self.append(response)
                self.statusTitle = L("Остановлено")
                self.statusDetail = L("Пакетная выгрузка остановлена пользователем.")
                self.lastResult = self.statusDetail
                self.currentStepLabel = L("Пакетная выгрузка остановлена.")
                self.resetBatchProgress()
                return
            }

            self.applyBatchResults(response, pendingItems: pendingItems)
            self.append(response)

            let processedCount = response.counts?.processed ?? Int(response.data["processedCount"] ?? "") ?? pendingItems.count
            let failedCount = pendingItems.filter { item in
                self.batchQueue.first(where: { $0.id == item.id })?.status == .failed
            }.count

            self.statusTitle = failedCount == 0 ? L("Готово") : L("Завершено с ошибками")
            self.statusDetail = L("Обработано {0} профилей. Сохранено файлов: {1}.", processedCount, self.savedStoriesCount)
            self.lastResult = self.statusDetail
            self.currentStepLabel = failedCount == 0 ? L("Очередь обработана.") : L("Очередь завершилась с ошибками.")
            if self.savedStoriesCount > 0 {
                self.triggerCelebration()
            }
            self.resetBatchProgress()
            await self.prepareEmptyStoryFolderCleanupPrompt()
        }
    }

    func stopBatchDownloads() {
        guard batchIsRunning else { return }
        batchStopRequested = true
        worker.stopCurrentProcess()
        statusTitle = L("Остановка")
        statusDetail = L("Останавливаю текущую выгрузку профиля...")
        appendLog(L("Запрошена остановка пакетной выгрузки."))
    }

    func copyLogs() {
        let orderedLogs = logs.reversed().joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(orderedLogs, forType: .string)
        appendLog(L("Логи скопированы в буфер обмена."))
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

    func removePendingEmptyStoryFolders() async {
        let folders = pendingEmptyStoryFolders
        pendingEmptyStoryFolders = []
        showEmptyFolderCleanupPrompt = false

        guard !folders.isEmpty else {
            emptyFolderCleanupReport = EmptyFolderCleanupReport(removedCount: 0, folderNames: [])
            return
        }

        await perform(L("Удаление пустых папок")) {
            let cleanup = await Task.detached(priority: .utility) {
                EmptyFolderCleanupService.deleteEmptyFolders(folders)
            }.value
            for folder in cleanup.failedFolders {
                self.appendLog(L("Не удалось удалить пустую папку {0}.", folder.lastPathComponent))
            }

            let removedNames = cleanup.removedFolderNames
            if !removedNames.isEmpty {
                self.appendLog(L("Удалены пустые папки после выгрузки stories: {0}.", removedNames.joined(separator: ", ")))
            }
            self.emptyFolderCleanupReport = EmptyFolderCleanupReport(removedCount: removedNames.count, folderNames: removedNames)
            self.statusTitle = cleanup.failedFolders.isEmpty ? L("Готово") : L("Завершено с ошибками")
            self.statusDetail = L("Удалено пустых папок: {0}.", removedNames.count)
            self.lastResult = self.statusDetail
        }
    }

    func parsedBatchLinks(from input: String) -> [String] {
        input
            .split { separator in
                separator.isWhitespace || separator == "," || separator == ";"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func normalizedProfileLink(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let lowercased = trimmed.lowercased()
        let urlSource = lowercased.contains("instagram.com") && !lowercased.contains("://")
            ? "https://\(trimmed)"
            : trimmed
        if let url = URL(string: urlSource), let host = url.host?.lowercased() {
            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https",
                  host == "instagram.com" || host.hasSuffix(".instagram.com")
            else {
                return ""
            }
            let pathParts = url.pathComponents.filter { $0 != "/" }
            guard let username = pathParts.first,
                  normalizedInstagramUsername(username) != nil,
                  !["accounts", "direct", "explore", "p", "reel", "reels", "stories"].contains(username.lowercased())
            else {
                return ""
            }
            return "https://www.instagram.com/\(username)/"
        }
        if lowercased.contains("instagram.com") {
            return ""
        }

        let stripped = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "*,;:!?/\\"))
        guard let username = normalizedInstagramUsername(stripped) else { return "" }
        return "https://www.instagram.com/\(username)/"
    }

    func normalizedBatchLinks(from input: String) -> [String] {
        var seen = Set<String>()
        return parsedBatchLinks(from: input)
            .map(normalizedProfileLink)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    func updateBatchProfile(id: UUID, status: BatchProfileItem.Status, message: String) {
        guard let index = batchQueue.firstIndex(where: { $0.id == id }) else { return }
        batchQueue[index].status = status
        batchQueue[index].message = message
    }

    func prepareEmptyStoryFolderCleanupPrompt() async {
        let directory = saveDirectory
        let emptyFolders = await Task.detached(priority: .utility) {
            EmptyFolderCleanupService.findDeletableEmptyFolders(in: directory)
        }.value
        guard !emptyFolders.isEmpty else {
            pendingEmptyStoryFolders = []
            showEmptyFolderCleanupPrompt = false
            return
        }
        pendingEmptyStoryFolders = emptyFolders
        showEmptyFolderCleanupPrompt = true
        appendLog(L("Найдены пустые папки после выгрузки stories: {0}.", emptyFolders.count))
    }

    func applyBatchResults(_ response: WorkerResponse, pendingItems: [BatchProfileItem]) {
        let found = response.counts?.found ?? Int(response.data["foundCount"] ?? "") ?? response.items.count
        let saved = response.counts?.saved ?? Int(response.data["savedCount"] ?? "") ?? response.items.count
        foundStoriesCount = found
        savedStoriesCount = saved

        let results: [BatchWorkerResult]
        if let structuredResults = response.batchResults, !structuredResults.isEmpty {
            results = structuredResults
        } else if let raw = response.data["batchResults"],
                  let data = raw.data(using: .utf8),
                  let legacyResults = try? JSONDecoder().decode([BatchWorkerResult].self, from: data) {
            results = legacyResults
        } else {
            for item in pendingItems {
                updateBatchProfile(
                    id: item.id,
                    status: response.ok ? .completed : .failed,
                    message: tr(response.message)
                )
            }
            return
        }

        let resultMap = results.reduce(into: [String: BatchWorkerResult]()) { result, item in
            let key = normalizedProfileLink(item.url).lowercased()
            if result[key] == nil {
                result[key] = item
            }
        }
        for item in pendingItems {
            let normalized = normalizedProfileLink(item.url).lowercased()
            guard let result = resultMap[normalized] else {
                updateBatchProfile(id: item.id, status: .failed, message: L("Для профиля нет результата пакетной выгрузки."))
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
            updateBatchProfile(id: item.id, status: status, message: tr(result.message))
        }
    }

    func resetBatchProgress() {
        batchIsRunning = false
        batchStopRequested = false
        batchCurrentIndex = 0
        batchTotalCount = 0
        batchRemainingCount = 0
        batchCurrentURL = ""
        batchProgressStartedURLs.removeAll()
        batchProgressCompletedURLs.removeAll()
    }

    func suggestedRecentListTitle(for urls: [String]) -> String {
        let normalized = urls.map(normalizedProfileLink)
        guard let first = normalized.first else { return L("Недавний список") }
        let username = first
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .last
            .map(String.init) ?? "profiles"
        return normalized.count == 1 ? username : "\(username) +\(normalized.count - 1)"
    }

    func loadRecentBatchLists() {
        guard !isDesignPreview else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.recentBatchListsKey),
              let decoded = try? JSONDecoder().decode([RecentBatchList].self, from: data) else {
            recentBatchLists = []
            return
        }
        recentBatchLists = decoded.compactMap { list in
            var seen = Set<String>()
            let validURLs = list.urls
                .map(normalizedProfileLink)
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            guard !validURLs.isEmpty else { return nil }
            return RecentBatchList(
                id: list.id,
                title: list.title,
                urls: validURLs,
                createdAt: list.createdAt
            )
        }
        if recentBatchLists != decoded {
            persistRecentBatchLists()
        }
    }

    func persistRecentBatchLists() {
        guard !isDesignPreview else { return }
        guard let data = try? JSONEncoder().encode(recentBatchLists) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentBatchListsKey)
    }

    func storeRecentBatchList(title: String, urls: [String]) {
        var seen = Set<String>()
        let normalizedURLs = urls
            .map(normalizedProfileLink)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard !normalizedURLs.isEmpty else { return }

        let normalizedIdentity = normalizedURLs.map { $0.lowercased() }
        recentBatchLists.removeAll { list in
            list.urls.map(normalizedProfileLink).map { $0.lowercased() } == normalizedIdentity
        }
        recentBatchLists.insert(
            RecentBatchList(title: title, urls: normalizedURLs),
            at: 0
        )
        if recentBatchLists.count > 8 {
            recentBatchLists = Array(recentBatchLists.prefix(8))
        }
        persistRecentBatchLists()
    }

    private func normalizedInstagramUsername(_ raw: String) -> String? {
        guard !raw.isEmpty,
              raw.count <= 30,
              raw.range(of: #"^[A-Za-z0-9._]+$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        return raw
    }
}
