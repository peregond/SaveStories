import AppKit
import Foundation

extension AppModel {
    func chooseSortingSourceDirectory() {
        guard !isBusy else {
            appendLog("Выбор папки источника пропущен: дождись завершения текущей операции.")
            return
        }

        presentDirectoryChooser(initialDirectory: sortingSourceDirectory ?? saveDirectory, canCreateDirectories: false) { url in
            self.sortingSourceDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.sortingSourceDirectoryKey)
            self.postProcessingSummary = "Источник сортировки выбран: \(url.lastPathComponent)."
            self.appendLog("Папка источника сортировки изменена на \(url.path).")
        }
    }

    func openSortingSourceDirectory() {
        guard let sortingSourceDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([sortingSourceDirectory])
    }

    func chooseEmptyFolderCleanupDirectory() {
        guard !isBusy else {
            appendLog("Выбор папки для очистки пропущен: дождись завершения текущей операции.")
            return
        }

        presentDirectoryChooser(initialDirectory: emptyFolderCleanupDirectory ?? sortingSourceDirectory ?? saveDirectory, canCreateDirectories: false) { url in
            self.emptyFolderCleanupDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.emptyFolderCleanupDirectoryKey)
            self.emptyFolderCleanupSummary = "Папка для очистки выбрана: \(url.lastPathComponent)."
            self.postProcessingSummary = "Папка для очистки выбрана: \(url.lastPathComponent)."
            self.appendLog("Папка для очистки пустых подпапок изменена на \(url.path).")
        }
    }

    func openEmptyFolderCleanupDirectory() {
        guard let emptyFolderCleanupDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([emptyFolderCleanupDirectory])
    }

    func removeEmptyFoldersInCleanupDirectory() async {
        guard !isBusy else { return }
        guard let emptyFolderCleanupDirectory else {
            emptyFolderCleanupSummary = "Сначала выбери папку, внутри которой нужно удалить пустые подпапки."
            postProcessingSummary = "Сначала выбери папку, внутри которой нужно удалить пустые подпапки."
            appendLog("Очистка пустых папок пропущена: папка не выбрана.")
            return
        }

        await perform("Очистка пустых папок") {
            self.currentStepLabel = "Проверяю подпапки в фоне."
            let candidateFolders = await Task.detached(priority: .utility) {
                EmptyFolderCleanupService.findDeletableEmptyFolders(in: emptyFolderCleanupDirectory)
            }.value
            guard !candidateFolders.isEmpty else {
                self.emptyFolderCleanupSummary = "Пустых папок в выбранной папке не найдено."
                self.postProcessingSummary = self.emptyFolderCleanupSummary
                self.statusTitle = "Готово"
                self.statusDetail = self.emptyFolderCleanupSummary
                self.lastResult = self.emptyFolderCleanupSummary
                self.currentStepLabel = "Проверка пустых папок завершена."
                self.appendLog("Очистка пустых папок: в \(emptyFolderCleanupDirectory.path) ничего не найдено.")
                return
            }

            self.currentStepLabel = "Удаляю только действительно пустые папки."
            let cleanup = await Task.detached(priority: .utility) {
                EmptyFolderCleanupService.deleteEmptyFolders(candidateFolders)
            }.value
            for folder in cleanup.failedFolders {
                self.appendLog("Не удалось удалить пустую папку \(folder.path).")
            }

            let removedNames = cleanup.removedFolderNames
            let failedCount = cleanup.failedFolders.count
            let message = failedCount == 0
                ? "Удалено пустых папок: \(removedNames.count)."
                : "Удалено пустых папок: \(removedNames.count). Ошибок: \(failedCount)."
            self.emptyFolderCleanupSummary = removedNames.isEmpty && failedCount == 0
                ? "Пустых папок в выбранной папке не найдено."
                : message
            self.postProcessingSummary = message
            self.statusTitle = failedCount == 0 ? "Готово" : "Завершено с ошибками"
            self.statusDetail = message
            self.lastResult = message
            self.currentStepLabel = "Очистка пустых папок завершена."
            self.appendLog("\(message) Папка: \(emptyFolderCleanupDirectory.path).")
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
            googleDriveLinkSummary = "Нет файлов для получения ссылок Google Drive."
            appendLog("Сборщик ссылок Google Drive пропущен: список файлов пуст.")
            return
        }

        await perform("Сбор ссылок Google Drive") {
            self.currentStepLabel = "Собираю Google Drive ссылки для подготовленных файлов."
            self.googleDriveLinkSummary = "Пробую собрать ссылки Google Drive для \(records.count) файлов."

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
                self.googleDriveLinkSummary = "Google Drive ссылки собраны: \(successCount). Результат скопирован в буфер."
            } else {
                self.googleDriveLinkSummary = "Ссылки собраны: \(successCount). Ошибок: \(failureCount). Сводка скопирована в буфер."
            }

            self.statusTitle = failureCount == 0 ? "Готово" : "Завершено с ошибками"
            self.statusDetail = self.googleDriveLinkSummary
            self.lastResult = self.googleDriveLinkSummary
            self.currentStepLabel = failureCount == 0 ? "Google Drive ссылки собраны." : "Часть ссылок не удалось получить автоматически."
            self.appendLog(self.googleDriveLinkSummary)

            for failed in outcomes.filter({ $0.errorMessage != nil }) {
                self.appendLog("Google Drive: \(URL(fileURLWithPath: failed.record.filePath).lastPathComponent) — \(failed.errorMessage ?? "неизвестная ошибка")")
            }
        }
    }

    func chooseDistributionRootDirectory() {
        guard !isBusy else {
            appendLog("Выбор папки раскладки пропущен: дождись завершения текущей операции.")
            return
        }

        presentDirectoryChooser(initialDirectory: distributionRootDirectory ?? saveDirectory, canCreateDirectories: true) { url in
            self.distributionRootDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.distributionRootDirectoryKey)
            self.postProcessingSummary = "Папка раскладки выбрана: \(url.lastPathComponent)."
            self.appendLog("Папка раскладки изменена на \(url.path).")
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
            postProcessingSummary = "Сначала выбери папку-источник, например Перенос."
            appendLog("Сортировка остановлена: не выбрана папка Перенос.")
            return
        }
        guard let distributionRootDirectory else {
            postProcessingSummary = "Сначала выбери базовую папку назначения."
            appendLog("Сортировка остановлена: не выбрана папка назначения.")
            return
        }

        let source = sortingSourceDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let destination = distributionRootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let sourcePrefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
        guard destination.path != source.path, !destination.path.hasPrefix(sourcePrefix) else {
            postProcessingSummary = "Папка назначения не должна совпадать с источником или находиться внутри него."
            statusTitle = "Ошибка"
            statusDetail = postProcessingSummary
            lastResult = postProcessingSummary
            appendLog("Сортировка остановлена: источник и назначение пересекаются.")
            return
        }

        let mapping = parsedFolderRoutingRules()

        await perform("Сортировка файлов") {
            self.currentStepLabel = "Читаю папку «На перенос» в фоне."
            do {
                let scan = try await Task.detached(priority: .userInitiated) {
                    try FileDistributionService.scanInputs(in: sortingSourceDirectory, mapping: mapping)
                }.value

                guard !scan.inputs.isEmpty else {
                    self.postProcessingSummary = "В выбранной папке нет файлов для сортировки."
                    self.statusTitle = "Готово"
                    self.statusDetail = self.postProcessingSummary
                    self.lastResult = self.postProcessingSummary
                    self.currentStepLabel = "Файлов для переноса не найдено."
                    self.appendLog("Сортировка: в папке \(sortingSourceDirectory.lastPathComponent) нет файлов для переноса.")
                    return
                }

                self.currentStepLabel = "Переношу файлы по правилам."
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
                self.statusTitle = "Ошибка"
                self.statusDetail = self.postProcessingSummary
                self.lastResult = self.postProcessingSummary
                self.currentStepLabel = "Сортировка завершилась ошибкой."
                self.appendLog("Сортировка: \(error.localizedDescription)")
            }
        }
    }

    func distributeLatestDownloadedFiles() async {
        guard !isBusy else { return }
        guard !latestSessionDownloadedItems.isEmpty else {
            postProcessingSummary = "Нет файлов из последней выгрузки для раскладки."
            appendLog("Постобработка пропущена: нет файлов последней выгрузки.")
            return
        }
        guard let distributionRootDirectory else {
            postProcessingSummary = "Сначала выбери папку, внутри которой лежат конечные подпапки."
            appendLog("Постобработка остановлена: не выбрана папка раскладки.")
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

        await perform("Сортировка последней выгрузки") {
            self.currentStepLabel = "Переношу файлы последней выгрузки в фоне."
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
            postProcessingSummary = "Нет списка для копирования."
            appendLog("Список для постобработки пуст.")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        postProcessingSummary = "Список папок и файлов скопирован в буфер."
        appendLog("Список разложенных файлов скопирован в буфер обмена.")
    }

    func undoLastDistribution() async {
        guard !isBusy else { return }

        let undoItems = postProcessedItems.filter { $0.originalPath != $0.currentPath }
        guard !undoItems.isEmpty else {
            postProcessingSummary = "Нет переноса для отмены."
            appendLog("Отмена переноса пропущена: нет последнего переноса.")
            return
        }

        let inputs = undoItems.map {
            FileDistributionUndoInput(
                id: $0.id,
                currentURL: URL(fileURLWithPath: $0.currentPath),
                originalURL: URL(fileURLWithPath: $0.originalPath)
            )
        }

        await perform("Отмена переноса") {
            self.currentStepLabel = "Возвращаю файлы в исходные папки в фоне."
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
            self.googleDriveLinkSummary = "Перенос отменён. После новой сортировки Drive-ссылки нужно собрать заново."

            let failedItems = undoItems.filter { result.failedIDs.contains($0.id) }
            if result.failedFileNames.isEmpty {
                self.postProcessedItems = []
                self.postProcessingSummary = "Отменён перенос файлов: \(result.restoredRecords.count)."
            } else {
                self.postProcessedItems = failedItems
                self.postProcessingSummary = "Отменён перенос файлов: \(result.restoredRecords.count). Ошибок: \(result.failedFileNames.count)."
                self.appendLog("Не удалось вернуть файлов: \(result.failedFileNames.joined(separator: ", ")).")
            }
            self.statusTitle = result.failedFileNames.isEmpty ? "Готово" : "Завершено с ошибками"
            self.statusDetail = self.postProcessingSummary
            self.lastResult = self.postProcessingSummary
            self.currentStepLabel = "Отмена переноса завершена."
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
                    return "# не удалось получить ссылку: \(filename)"
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
                        return "# не удалось получить ссылку: \(filename)"
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
        return components.first ?? "Без страны"
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
        guard !isBusy, !isRefreshingNotionRoutingRules else { return false }

        if !force, wasNotionSourceRefreshedToday(key: Self.notionRoutingRulesLastRefreshAtKey) {
            let cachedRules = UserDefaults.standard.string(forKey: Self.notionRoutingRulesCachedRulesKey) ?? folderRoutingRules
            guard !cachedRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notionRoutingRulesSourceSummary = "Notion уже обновлялся сегодня, но сохранённые правила пустые."
                postProcessingSummary = notionRoutingRulesSourceSummary
                appendLog("Повторная загрузка правил Notion пропущена: сегодня уже обновляли, сохранённые правила пустые.")
                return false
            }

            folderRoutingRules = cachedRules
            persistFolderRoutingRules()
            let count = cachedRules.split(whereSeparator: \.isNewline).count
            notionRoutingRulesSourceSummary = "Notion уже обновлялся сегодня: использую сохранённые правила (\(count))."
            postProcessingSummary = notionRoutingRulesSourceSummary
            currentStepLabel = "Использую сохранённые правила Notion."
            appendLog("Повторная загрузка правил Notion пропущена: применены сохранённые правила, строк: \(count).")
            return true
        }

        isRefreshingNotionRoutingRules = true
        notionRoutingRulesSourceSummary = "Загружаю правила сортировки из Notion..."
        postProcessingSummary = "Загружаю правила сортировки из Notion..."
        currentStepLabel = "Получаю правила сортировки из Notion."
        defer { isRefreshingNotionRoutingRules = false }

        do {
            let rules = try await NotionRoutingRulesSource().fetchRules()
            guard !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notionRoutingRulesSourceSummary = "В Notion не найдено правил сортировки."
                postProcessingSummary = notionRoutingRulesSourceSummary
                appendLog("В Notion не найдено правил сортировки.")
                return false
            }

            folderRoutingRules = rules
            persistFolderRoutingRules()
            UserDefaults.standard.set(rules, forKey: Self.notionRoutingRulesCachedRulesKey)
            markNotionSourceRefreshed(key: Self.notionRoutingRulesLastRefreshAtKey)
            let count = rules.split(whereSeparator: \.isNewline).count
            notionRoutingRulesSourceSummary = "Notion обновлён: \(count) правил."
            postProcessingSummary = notionRoutingRulesSourceSummary
            currentStepLabel = "Правила Notion загружены."
            appendLog("Правила сортировки заменены Notion-списком: \(count).")
            return true
        } catch {
            notionRoutingRulesSourceSummary = "Не удалось обновить правила Notion: \(error.localizedDescription)"
            postProcessingSummary = notionRoutingRulesSourceSummary
            statusTitle = "Ошибка Notion"
            statusDetail = notionRoutingRulesSourceSummary
            currentStepLabel = "Правила Notion не загружены."
            appendLog("Не удалось загрузить правила Notion: \(error.localizedDescription)")
            return false
        }
    }

    private func saveRememberedBloggers() {
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
            googleDriveLinkSummary = "После новой сортировки Drive-ссылки нужно собрать заново."
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
            postProcessingSummary = "Разложено файлов: \(result.movedCount). Подпапок затронуто: \(Set(records.map(\.targetFolderName)).count)."
        } else if !records.isEmpty && failureCount == 0 {
            postProcessingSummary = "Файлы уже лежат в нужных папках."
        } else {
            postProcessingSummary = "Не удалось разложить файлы: \(failureCount)."
        }

        if !result.failedFileNames.isEmpty {
            appendLog("Не удалось обработать файлов: \(result.failedFileNames.joined(separator: ", ")).")
        }
        if !unreadableFolderNames.isEmpty {
            appendLog("Не удалось прочитать папки: \(unreadableFolderNames.joined(separator: ", ")).")
        }

        statusTitle = failureCount == 0 ? "Готово" : "Завершено с ошибками"
        statusDetail = postProcessingSummary
        lastResult = postProcessingSummary
        currentStepLabel = failureCount == 0 ? "Сортировка завершена." : "Сортировка завершена с ошибками."
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
