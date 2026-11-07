import AppKit
import Foundation

extension AppModel {
    func chooseSortingSourceDirectory() {
        guard !isBusy else {
            appendLog(L("Выбор папки источника пропущен: дождись завершения текущей операции."))
            return
        }

        presentDirectoryChooser(initialDirectory: sortingSourceDirectory ?? saveDirectory, canCreateDirectories: false) { url in
            self.sortingSourceDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.sortingSourceDirectoryKey)
            self.postProcessingSummary = L("Источник сортировки выбран: {0}.", url.lastPathComponent)
            self.appendLog(L("Папка источника сортировки изменена на {0}.", url.path))
        }
    }

    func openSortingSourceDirectory() {
        guard let sortingSourceDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([sortingSourceDirectory])
    }

    func chooseEmptyFolderCleanupDirectory() {
        guard !isBusy else {
            appendLog(L("Выбор папки для очистки пропущен: дождись завершения текущей операции."))
            return
        }

        presentDirectoryChooser(initialDirectory: emptyFolderCleanupDirectory ?? sortingSourceDirectory ?? saveDirectory, canCreateDirectories: false) { url in
            self.emptyFolderCleanupDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.emptyFolderCleanupDirectoryKey)
            self.emptyFolderCleanupSummary = L("Папка для очистки выбрана: {0}.", url.lastPathComponent)
            self.postProcessingSummary = L("Папка для очистки выбрана: {0}.", url.lastPathComponent)
            self.appendLog(L("Папка для очистки пустых подпапок изменена на {0}.", url.path))
        }
    }

    func openEmptyFolderCleanupDirectory() {
        guard let emptyFolderCleanupDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([emptyFolderCleanupDirectory])
    }

    func removeEmptyFoldersInCleanupDirectory() async {
        guard !isBusy else { return }
        guard let emptyFolderCleanupDirectory else {
            emptyFolderCleanupSummary = L("Сначала выбери папку, внутри которой нужно удалить пустые подпапки.")
            postProcessingSummary = L("Сначала выбери папку, внутри которой нужно удалить пустые подпапки.")
            appendLog(L("Очистка пустых папок пропущена: папка не выбрана."))
            return
        }

        await perform(L("Очистка пустых папок")) {
            self.currentStepLabel = L("Проверяю подпапки в фоне.")
            let candidateFolders = await Task.detached(priority: .utility) {
                EmptyFolderCleanupService.findDeletableEmptyFolders(in: emptyFolderCleanupDirectory)
            }.value
            guard !candidateFolders.isEmpty else {
                self.emptyFolderCleanupSummary = L("Пустых папок в выбранной папке не найдено.")
                self.postProcessingSummary = self.emptyFolderCleanupSummary
                self.statusTitle = L("Готово")
                self.statusDetail = self.emptyFolderCleanupSummary
                self.lastResult = self.emptyFolderCleanupSummary
                self.currentStepLabel = L("Проверка пустых папок завершена.")
                self.appendLog(L("Очистка пустых папок: в {0} ничего не найдено.", emptyFolderCleanupDirectory.path))
                return
            }

            self.currentStepLabel = L("Удаляю только действительно пустые папки.")
            let cleanup = await Task.detached(priority: .utility) {
                EmptyFolderCleanupService.deleteEmptyFolders(candidateFolders)
            }.value
            for folder in cleanup.failedFolders {
                self.appendLog(L("Не удалось удалить пустую папку {0}.", folder.path))
            }

            let removedNames = cleanup.removedFolderNames
            let failedCount = cleanup.failedFolders.count
            let message = failedCount == 0
                ? L("Удалено пустых папок: {0}.", removedNames.count)
                : L("Удалено пустых папок: {0}. Ошибок: {1}.", removedNames.count, failedCount)
            self.emptyFolderCleanupSummary = removedNames.isEmpty && failedCount == 0
                ? L("Пустых папок в выбранной папке не найдено.")
                : message
            self.postProcessingSummary = message
            self.statusTitle = failedCount == 0 ? L("Готово") : L("Завершено с ошибками")
            self.statusDetail = message
            self.lastResult = message
            self.currentStepLabel = L("Очистка пустых папок завершена.")
            self.appendLog(L("{0} Папка: {1}.", message, emptyFolderCleanupDirectory.path))
        }
    }

    func openSystemSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
              NSWorkspace.shared.open(settingsURL)
        else {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
    }

    func exportGoogleDriveLinks() async {
        let records = currentPostProcessingRecords()
        guard !records.isEmpty else {
            googleDriveLinkSummary = L("Нет файлов для получения ссылок Google Drive.")
            appendLog(L("Сборщик ссылок Google Drive пропущен: список файлов пуст."))
            return
        }

        await perform(L("Сбор ссылок Google Drive")) {
            self.currentStepLabel = L("Собираю Google Drive ссылки для подготовленных файлов.")
            self.googleDriveLinkSummary = L("Пробую собрать ссылки Google Drive для {0} файлов.", records.count)

            let exporter = GoogleDriveLinkExporter()
            let outcomes = await exporter.exportLinks(
                for: records.map {
                    GoogleDriveLinkExporter.ExportRecord(
                        id: $0.id,
                        header: $0.reportHeader,
                        filePath: $0.currentPath
                    )
                }
            )

            let report = self.buildDigestReport(from: outcomes)
            let successCount = outcomes.filter { $0.link != nil }.count
            let failureCount = outcomes.count - successCount

            if !report.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
            }

            if failureCount == 0 {
                self.googleDriveLinkSummary = L("Google Drive ссылки собраны: {0}. Результат скопирован в буфер.", successCount)
            } else {
                self.googleDriveLinkSummary = L("Ссылки собраны: {0}. Ошибок: {1}. Сводка скопирована в буфер.", successCount, failureCount)
            }

            self.statusTitle = failureCount == 0 ? L("Готово") : L("Завершено с ошибками")
            self.statusDetail = self.googleDriveLinkSummary
            self.lastResult = self.googleDriveLinkSummary
            self.currentStepLabel = failureCount == 0 ? L("Google Drive ссылки собраны.") : L("Часть ссылок не удалось получить автоматически.")
            self.appendLog(self.googleDriveLinkSummary)

            for failed in outcomes.filter({ $0.errorMessage != nil }) {
                self.appendLog("Google Drive: \(URL(fileURLWithPath: failed.record.filePath).lastPathComponent) — \(failed.errorMessage ?? "неизвестная ошибка")")
            }
        }
    }

    func chooseDistributionRootDirectory() {
        guard !isBusy else {
            appendLog(L("Выбор папки раскладки пропущен: дождись завершения текущей операции."))
            return
        }

        presentDirectoryChooser(initialDirectory: distributionRootDirectory ?? saveDirectory, canCreateDirectories: true) { url in
            self.distributionRootDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.distributionRootDirectoryKey)
            self.postProcessingSummary = L("Папка раскладки выбрана: {0}.", url.lastPathComponent)
            self.appendLog(L("Папка раскладки изменена на {0}.", url.path))
        }
    }

    func openDistributionRootDirectory() {
        guard let distributionRootDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([distributionRootDirectory])
    }

    func distributeFilesFromSortingSource(skipNotionRefresh: Bool = false) async {
        guard !isBusy else { return }
        if notionRoutingRulesSourceEnabled && !skipNotionRefresh {
            guard await refreshNotionRoutingRules() else { return }
        }
        guard let sortingSourceDirectory else {
            postProcessingSummary = L("Сначала выбери папку-источник, например Перенос.")
            appendLog(L("Сортировка остановлена: не выбрана папка Перенос."))
            return
        }
        guard let distributionRootDirectory else {
            postProcessingSummary = L("Сначала выбери базовую папку назначения.")
            appendLog(L("Сортировка остановлена: не выбрана папка назначения."))
            return
        }

        let source = sortingSourceDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let destination = distributionRootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let sourcePrefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
        guard destination.path != source.path, !destination.path.hasPrefix(sourcePrefix) else {
            postProcessingSummary = L("Папка назначения не должна совпадать с источником или находиться внутри него.")
            statusTitle = L("Ошибка")
            statusDetail = postProcessingSummary
            lastResult = postProcessingSummary
            appendLog(L("Сортировка остановлена: источник и назначение пересекаются."))
            return
        }

        let mapping = parsedFolderRoutingRules()

        await perform(L("Сортировка файлов")) {
            self.currentStepLabel = L("Читаю папку «На перенос» в фоне.")
            do {
                let scan = try await Task.detached(priority: .userInitiated) {
                    try FileDistributionService.scanInputs(in: sortingSourceDirectory, mapping: mapping)
                }.value

                guard !scan.inputs.isEmpty else {
                    self.postProcessingSummary = L("В выбранной папке нет файлов для сортировки.")
                    self.statusTitle = L("Готово")
                    self.statusDetail = self.postProcessingSummary
                    self.lastResult = self.postProcessingSummary
                    self.currentStepLabel = L("Файлов для переноса не найдено.")
                    self.appendLog(L("Сортировка: в папке {0} нет файлов для переноса.", sortingSourceDirectory.lastPathComponent))
                    return
                }

                self.currentStepLabel = L("Переношу файлы по правилам.")
                let result = await Task.detached(priority: .userInitiated) {
                    FileDistributionService.distribute(inputs: scan.inputs, destinationRoot: distributionRootDirectory)
                }.value
                self.applyDistributionResult(
                    result,
                    shouldSynchronizeLatestSession: false,
                    unreadableFolderNames: scan.unreadableFolderNames
                )
            } catch {
                self.postProcessingSummary = error.localizedDescription
                self.statusTitle = L("Ошибка")
                self.statusDetail = self.postProcessingSummary
                self.lastResult = self.postProcessingSummary
                self.currentStepLabel = L("Сортировка завершилась ошибкой.")
                self.appendLog(L("Сортировка: {0}", error.localizedDescription))
            }
        }
    }

    func distributeLatestDownloadedFiles() async {
        guard !isBusy else { return }
        guard !latestSessionDownloadedItems.isEmpty else {
            postProcessingSummary = L("Нет файлов из последней выгрузки для раскладки.")
            appendLog(L("Постобработка пропущена: нет файлов последней выгрузки."))
            return
        }
        guard let distributionRootDirectory else {
            postProcessingSummary = L("Сначала выбери папку, внутри которой лежат конечные подпапки.")
            appendLog(L("Постобработка остановлена: не выбрана папка раскладки."))
            return
        }

        let mapping = parsedFolderRoutingRules()
        let inputs = latestSessionDownloadedItems.map { item in
            let username = sourceUsername(for: item)
            return FileDistributionInput(
                id: item.id,
                originalUsername: username,
                currentURL: resolvedCurrentURL(for: item),
                targetRelativeFolder: targetRelativeFolderPath(for: username, mapping: mapping)
            )
        }

        await perform(L("Сортировка последней выгрузки")) {
            self.currentStepLabel = L("Переношу файлы последней выгрузки в фоне.")
            let result = await Task.detached(priority: .userInitiated) {
                FileDistributionService.distribute(inputs: inputs, destinationRoot: distributionRootDirectory)
            }.value
            self.applyDistributionResult(
                result,
                shouldSynchronizeLatestSession: true,
                unreadableFolderNames: []
            )
        }
    }

    func copyPostProcessedReport() {
        let report = buildPostProcessedReport()
        guard !report.isEmpty else {
            postProcessingSummary = L("Нет списка для копирования.")
            appendLog(L("Список для постобработки пуст."))
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        postProcessingSummary = L("Список папок и файлов скопирован в буфер.")
        appendLog(L("Список разложенных файлов скопирован в буфер обмена."))
    }

    func undoLastDistribution() async {
        guard !isBusy else { return }

        let undoItems = postProcessedItems.filter { $0.originalPath != $0.currentPath }
        guard !undoItems.isEmpty else {
            postProcessingSummary = L("Нет переноса для отмены.")
            appendLog(L("Отмена переноса пропущена: нет последнего переноса."))
            return
        }

        let inputs = undoItems.map {
            FileDistributionUndoInput(
                id: $0.id,
                currentURL: URL(fileURLWithPath: $0.currentPath),
                originalURL: URL(fileURLWithPath: $0.originalPath)
            )
        }

        await perform(L("Отмена переноса")) {
            self.currentStepLabel = L("Возвращаю файлы в исходные папки в фоне.")
            let result = await Task.detached(priority: .userInitiated) {
                FileDistributionService.undo(inputs)
            }.value
            let restoredPaths = result.restoredRecords.reduce(into: [String: String]()) { paths, record in
                paths[record.id] = record.restoredURL.path
            }

            self.latestSessionDownloadedItems = self.latestSessionDownloadedItems.map { item in
                guard let restoredPath = restoredPaths[item.id] else { return item }
                return item.with(localPath: restoredPath)
            }
            self.synchronizeDownloadedItems(with: self.latestSessionDownloadedItems)
            self.googleDriveLinkSummary = L("Перенос отменён. После новой сортировки Drive-ссылки нужно собрать заново.")

            let failedItems = undoItems.filter { result.failedIDs.contains($0.id) }
            if result.failedFileNames.isEmpty {
                self.postProcessedItems = []
                self.postProcessingSummary = L("Отменён перенос файлов: {0}.", result.restoredRecords.count)
            } else {
                self.postProcessedItems = failedItems
                self.postProcessingSummary = L("Отменён перенос файлов: {0}. Ошибок: {1}.", result.restoredRecords.count, result.failedFileNames.count)
                self.appendLog(L("Не удалось вернуть файлов: {0}.", result.failedFileNames.joined(separator: ", ")))
            }
            self.statusTitle = result.failedFileNames.isEmpty ? L("Готово") : L("Завершено с ошибками")
            self.statusDetail = self.postProcessingSummary
            self.lastResult = self.postProcessingSummary
            self.currentStepLabel = L("Отмена переноса завершена.")
            self.appendLog(self.postProcessingSummary)
        }
    }

    func parsedFolderRoutingRules() -> [String: String] {
        let mapping: [String: String] = folderRoutingRules
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { partialResult, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else { return }

                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return }
                partialResult[parts[0].lowercased()] = parts[1]
            }
        rememberBloggers(from: mapping)
        return mapping
    }

    func persistFolderRoutingRules() {
        guard !isDesignPreview else { return }
        UserDefaults.standard.set(folderRoutingRules, forKey: Self.folderRoutingRulesKey)
    }

    private func buildPostProcessedReport() -> String {
        let records = currentPostProcessingRecords()

        guard !records.isEmpty else { return "" }

        let grouped = Dictionary(grouping: records, by: \.reportHeader)
        let headers = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return headers.map { header in
            let items = (grouped[header] ?? [])
                .sorted { $0.currentPath.localizedStandardCompare($1.currentPath) == .orderedAscending }
                .map(\.currentPath)
                .joined(separator: "\n")
            return "\(header)\n\(items)"
        }
        .joined(separator: "\n\n")
    }

    private func currentPostProcessingRecords() -> [PostProcessedItem] {
        guard postProcessedItems.isEmpty else { return postProcessedItems }

        var seen = Set<String>()
        return latestSessionDownloadedItems
            .filter { seen.insert($0.id).inserted }
            .map {
                let username = sourceUsername(for: $0)
                let currentURL = resolvedCurrentURL(for: $0)
                return PostProcessedItem(
                    id: $0.id,
                    originalUsername: username,
                    targetFolderName: username,
                    originalPath: currentURL.path,
                    currentPath: currentURL.path
                )
            }
    }

    private func buildGoogleDriveLinkReport(from outcomes: [GoogleDriveLinkExporter.ExportOutcome]) -> String {
        guard !outcomes.isEmpty else { return "" }

        let grouped = Dictionary(grouping: outcomes, by: \.record.header)
        let headers = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return headers.map { header in
            let lines = (grouped[header] ?? [])
                .sorted { $0.record.filePath.localizedStandardCompare($1.record.filePath) == .orderedAscending }
                .map { outcome -> String in
                    if let link = outcome.link, !link.isEmpty {
                        return link
                    }
                    let filename = URL(fileURLWithPath: outcome.record.filePath).lastPathComponent
                    return L("# не удалось получить ссылку: {0}", filename)
                }
                .joined(separator: "\n")

            return "\(header)\n\(lines)"
        }
        .joined(separator: "\n\n")
    }

    private func buildDigestReport(from outcomes: [GoogleDriveLinkExporter.ExportOutcome]) -> String {
        guard !outcomes.isEmpty else { return "" }

        let recordsByID = currentPostProcessingRecords().reduce(into: [String: PostProcessedItem]()) { records, item in
            records[item.id] = item
        }
        let groupedByCountry = Dictionary(grouping: outcomes) { outcome in
            countryFolder(from: recordsByID[outcome.record.id]?.targetFolderName ?? outcome.record.header)
        }
        let countries = groupedByCountry.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        return countries.map { country in
            let byBlogger = Dictionary(grouping: groupedByCountry[country] ?? []) { outcome in
                recordsByID[outcome.record.id]?.originalUsername ?? outcome.record.header
            }
            let bloggerBlocks = byBlogger.keys.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            .map { blogger in
                let links = (byBlogger[blogger] ?? [])
                    .sorted { $0.record.filePath.localizedStandardCompare($1.record.filePath) == .orderedAscending }
                    .map { outcome -> String in
                        if let link = outcome.link, !link.isEmpty {
                            return link
                        }
                        let filename = URL(fileURLWithPath: outcome.record.filePath).lastPathComponent
                        return L("# не удалось получить ссылку: {0}", filename)
                    }
                    .joined(separator: "\n")
                return "\(blogger)\n\(links)"
            }
            .joined(separator: "\n\n")

            return "\(country)\n\n\(bloggerBlocks)"
        }
        .joined(separator: "\n\n")
    }

    private func targetRelativeFolderPath(for username: String, mapping: [String: String]) -> String {
        FileDistributionService.targetRelativeFolderPath(for: username, mapping: mapping)
    }

    private func countryFolder(from targetRelativeFolder: String) -> String {
        let components = targetRelativeFolder
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return components.first ?? L("Без страны")
    }

    private func rememberBloggers(from mapping: [String: String]) {
        guard !mapping.isEmpty else { return }

        let existing = rememberedBloggers.reduce(into: [String: RememberedBlogger]()) { bloggers, blogger in
            bloggers[blogger.id] = blogger
        }
        let merged = mapping.reduce(into: existing) { partialResult, entry in
            let username = entry.key
            let targetFolder = targetRelativeFolderPath(for: username, mapping: mapping)
            partialResult[username] = RememberedBlogger(
                username: username,
                countryFolder: countryFolder(from: targetFolder),
                targetFolder: targetFolder,
                lastUsedAt: Date()
            )
        }

        rememberedBloggers = merged.values.sorted {
            if $0.countryFolder == $1.countryFolder {
                return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
            }
            return $0.countryFolder.localizedCaseInsensitiveCompare($1.countryFolder) == .orderedAscending
        }
        saveRememberedBloggers()
    }

    private func rememberBloggers(from records: [PostProcessedItem]) {
        guard !records.isEmpty else { return }

        var merged = rememberedBloggers.reduce(into: [String: RememberedBlogger]()) { bloggers, blogger in
            bloggers[blogger.id] = blogger
        }
        for record in records {
            merged[record.originalUsername.lowercased()] = RememberedBlogger(
                username: record.originalUsername,
                countryFolder: countryFolder(from: record.targetFolderName),
                targetFolder: record.targetFolderName,
                lastUsedAt: Date()
            )
        }

        rememberedBloggers = merged.values.sorted {
            if $0.countryFolder == $1.countryFolder {
                return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
            }
            return $0.countryFolder.localizedCaseInsensitiveCompare($1.countryFolder) == .orderedAscending
        }
        saveRememberedBloggers()
    }

    func loadRememberedBloggers() {
        guard !isDesignPreview else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.rememberedBloggersKey),
              let decoded = try? JSONDecoder().decode([RememberedBlogger].self, from: data)
        else { return }
        let uniqueBloggers = decoded.reduce(into: [String: RememberedBlogger]()) { bloggers, blogger in
            if let existing = bloggers[blogger.id], existing.lastUsedAt >= blogger.lastUsedAt {
                return
            } else {
                bloggers[blogger.id] = blogger
            }
        }
        rememberedBloggers = uniqueBloggers.values.sorted {
            if $0.countryFolder == $1.countryFolder {
                return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
            }
            return $0.countryFolder.localizedCaseInsensitiveCompare($1.countryFolder) == .orderedAscending
        }
    }

    @discardableResult
    func refreshNotionRoutingRules(force: Bool = false) async -> Bool {
        guard !isDesignPreview, !isBusy, !isRefreshingNotionRoutingRules else { return false }

        if !force, wasNotionSourceRefreshedToday(key: Self.notionRoutingRulesLastRefreshAtKey) {
            let cachedRules = UserDefaults.standard.string(forKey: Self.notionRoutingRulesCachedRulesKey) ?? folderRoutingRules
            guard !cachedRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notionRoutingRulesSourceSummary = L("Notion уже обновлялся сегодня, но сохранённые правила пустые.")
                postProcessingSummary = notionRoutingRulesSourceSummary
                appendLog(L("Повторная загрузка правил Notion пропущена: сегодня уже обновляли, сохранённые правила пустые."))
                return false
            }

            folderRoutingRules = cachedRules
            persistFolderRoutingRules()
            let count = cachedRules.split(whereSeparator: \.isNewline).count
            notionRoutingRulesSourceSummary = L("Notion уже обновлялся сегодня: использую сохранённые правила ({0}).", count)
            postProcessingSummary = notionRoutingRulesSourceSummary
            currentStepLabel = L("Использую сохранённые правила Notion.")
            appendLog(L("Повторная загрузка правил Notion пропущена: применены сохранённые правила, строк: {0}.", count))
            return true
        }

        isRefreshingNotionRoutingRules = true
        notionRoutingRulesSourceSummary = L("Загружаю правила сортировки из Notion...")
        postProcessingSummary = L("Загружаю правила сортировки из Notion...")
        currentStepLabel = L("Получаю правила сортировки из Notion.")
        defer { isRefreshingNotionRoutingRules = false }

        do {
            let rules = try await NotionRoutingRulesSource().fetchRules()
            guard !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notionRoutingRulesSourceSummary = L("В Notion не найдено правил сортировки.")
                postProcessingSummary = notionRoutingRulesSourceSummary
                appendLog(L("В Notion не найдено правил сортировки."))
                return false
            }

            folderRoutingRules = rules
            persistFolderRoutingRules()
            UserDefaults.standard.set(rules, forKey: Self.notionRoutingRulesCachedRulesKey)
            markNotionSourceRefreshed(key: Self.notionRoutingRulesLastRefreshAtKey)
            let count = rules.split(whereSeparator: \.isNewline).count
            notionRoutingRulesSourceSummary = L("Notion обновлён: {0} правил.", count)
            postProcessingSummary = notionRoutingRulesSourceSummary
            currentStepLabel = L("Правила Notion загружены.")
            appendLog(L("Правила сортировки заменены Notion-списком: {0}.", count))
            return true
        } catch {
            notionRoutingRulesSourceSummary = L("Не удалось обновить правила Notion: {0}", error.localizedDescription)
            postProcessingSummary = notionRoutingRulesSourceSummary
            statusTitle = L("Ошибка Notion")
            statusDetail = notionRoutingRulesSourceSummary
            currentStepLabel = L("Правила Notion не загружены.")
            appendLog(L("Не удалось загрузить правила Notion: {0}", error.localizedDescription))
            return false
        }
    }

    private func saveRememberedBloggers() {
        guard !isDesignPreview else { return }
        guard let data = try? JSONEncoder().encode(rememberedBloggers) else { return }
        UserDefaults.standard.set(data, forKey: Self.rememberedBloggersKey)
    }

    private func sourceUsername(for item: WorkerItem) -> String {
        if let existing = postProcessedItems.first(where: { $0.id == item.id }) {
            return existing.originalUsername
        }
        return URL(fileURLWithPath: item.localPath).deletingLastPathComponent().lastPathComponent
    }

    private func resolvedCurrentURL(for item: WorkerItem) -> URL {
        if let existing = postProcessedItems.first(where: { $0.id == item.id }) {
            return URL(fileURLWithPath: existing.currentPath)
        }
        return URL(fileURLWithPath: item.localPath)
    }

    private func synchronizeDownloadedItems(with updatedItems: [WorkerItem]) {
        let updatedMap = updatedItems.reduce(into: [String: WorkerItem]()) { items, item in
            items[item.id] = item
        }
        downloadedItems = downloadedItems.map { item in
            updatedMap[item.id] ?? item
        }
    }

    private func applyDistributionResult(
        _ result: FileDistributionResult,
        shouldSynchronizeLatestSession: Bool,
        unreadableFolderNames: [String]
    ) {
        let records = result.records.map {
            PostProcessedItem(
                id: $0.id,
                originalUsername: $0.originalUsername,
                targetFolderName: $0.targetRelativeFolder,
                originalPath: $0.originalURL.path,
                currentPath: $0.currentURL.path
            )
        }

        if !records.isEmpty {
            postProcessedItems = records.sorted {
                if $0.targetFolderName == $1.targetFolderName {
                    return $0.currentPath.localizedStandardCompare($1.currentPath) == .orderedAscending
                }
                return $0.targetFolderName.localizedCaseInsensitiveCompare($1.targetFolderName) == .orderedAscending
            }
            rememberBloggers(from: postProcessedItems)
            googleDriveLinkSummary = L("После новой сортировки Drive-ссылки нужно собрать заново.")
        }

        if shouldSynchronizeLatestSession {
            let updatedPaths = result.records.reduce(into: [String: String]()) { paths, record in
                paths[record.id] = record.currentURL.path
            }
            latestSessionDownloadedItems = latestSessionDownloadedItems.map { item in
                guard let updatedPath = updatedPaths[item.id] else { return item }
                return item.with(localPath: updatedPath)
            }
            synchronizeDownloadedItems(with: latestSessionDownloadedItems)
        }

        let failureCount = result.failedFileNames.count + unreadableFolderNames.count
        if result.movedCount > 0 {
            postProcessingSummary = L("Разложено файлов: {0}. Подпапок затронуто: {1}.", result.movedCount, Set(records.map(\.targetFolderName)).count)
        } else if !records.isEmpty && failureCount == 0 {
            postProcessingSummary = L("Файлы уже лежат в нужных папках.")
        } else {
            postProcessingSummary = L("Не удалось разложить файлы: {0}.", failureCount)
        }

        if !result.failedFileNames.isEmpty {
            appendLog(L("Не удалось обработать файлов: {0}.", result.failedFileNames.joined(separator: ", ")))
        }
        if !unreadableFolderNames.isEmpty {
            appendLog(L("Не удалось прочитать папки: {0}.", unreadableFolderNames.joined(separator: ", ")))
        }

        statusTitle = failureCount == 0 ? L("Готово") : L("Завершено с ошибками")
        statusDetail = postProcessingSummary
        lastResult = postProcessingSummary
        currentStepLabel = failureCount == 0 ? L("Сортировка завершена.") : L("Сортировка завершена с ошибками.")
        appendLog(postProcessingSummary)
    }
}

private extension WorkerItem {
    func with(localPath: String) -> WorkerItem {
        WorkerItem(
            id: id,
            sourceURL: sourceURL,
            pageURL: pageURL,
            localPath: localPath,
            metadataPath: metadataPath,
            mediaType: mediaType,
            createdAt: createdAt
        )
    }
}
