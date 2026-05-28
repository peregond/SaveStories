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

    func removeEmptyFoldersInCleanupDirectory() {
        guard !isBusy else { return }
        guard let emptyFolderCleanupDirectory else {
            emptyFolderCleanupSummary = "Сначала выбери папку, внутри которой нужно удалить пустые подпапки."
            postProcessingSummary = "Сначала выбери папку, внутри которой нужно удалить пустые подпапки."
            appendLog("Очистка пустых папок пропущена: папка не выбрана.")
            return
        }

        let candidateFolders = EmptyFolderCleanupService.findDeletableEmptyFolders(in: emptyFolderCleanupDirectory)
        guard !candidateFolders.isEmpty else {
            emptyFolderCleanupSummary = "В выбранной папке нет подпапок для проверки."
            postProcessingSummary = "Пустых папок в выбранной папке не найдено."
            appendLog("Очистка пустых папок: в \(emptyFolderCleanupDirectory.path) ничего не найдено.")
            return
        }

        let cleanup = EmptyFolderCleanupService.deleteEmptyFolders(candidateFolders)
        for folder in cleanup.failedFolders {
            appendLog("Не удалось удалить пустую папку \(folder.path).")
        }

        let removedNames = cleanup.removedFolderNames
        let failedCount = cleanup.failedFolders.count
        let message = failedCount == 0
            ? "Удалено пустых папок: \(removedNames.count)."
            : "Удалено пустых папок: \(removedNames.count). Ошибок: \(failedCount)."
        emptyFolderCleanupSummary = removedNames.isEmpty && failedCount == 0
            ? "Пустых папок в выбранной папке не найдено."
            : message
        postProcessingSummary = message
        statusTitle = failedCount == 0 ? "Готово" : "Завершено с ошибками"
        statusDetail = message
        lastResult = message
        currentStepLabel = "Очистка пустых папок завершена."
        appendLog("\(message) Папка: \(emptyFolderCleanupDirectory.path).")
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

    func distributeFilesFromSortingSource(skipNotionRefresh: Bool = false) {
        guard !isBusy else { return }
        if notionRoutingRulesSourceEnabled && !skipNotionRefresh {
            Task {
                let refreshed = await refreshNotionRoutingRules()
                if refreshed {
                    distributeFilesFromSortingSource(skipNotionRefresh: true)
                }
            }
            return
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

        let manager = FileManager.default
        let mapping = parsedFolderRoutingRules()

        guard let creatorFolders = try? manager.contentsOfDirectory(
            at: sortingSourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) else {
            postProcessingSummary = "Не удалось прочитать содержимое папки источника."
            appendLog("Сортировка: не удалось прочитать папку \(sortingSourceDirectory.path).")
            return
        }

        let inputs = creatorFolders.flatMap { creatorFolder -> [FileDistributionInput] in
            let creatorName = creatorFolder.lastPathComponent
            let files = (try? manager.contentsOfDirectory(
                at: creatorFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            return files.compactMap { candidate in
                guard (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return nil
                }
                return FileDistributionInput(
                    id: candidate.path,
                    originalUsername: creatorName,
                    currentURL: candidate,
                    targetRelativeFolder: targetRelativeFolderPath(for: creatorName, mapping: mapping)
                )
            }
        }

        guard !inputs.isEmpty else {
            postProcessingSummary = "В выбранной папке нет файлов для сортировки."
            appendLog("Сортировка: в папке \(sortingSourceDirectory.lastPathComponent) нет файлов для переноса.")
            return
        }

        distribute(inputs: inputs, destinationRoot: distributionRootDirectory, shouldSynchronizeLatestSession: false)
    }

    func distributeLatestDownloadedFiles() {
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

        let manager = FileManager.default
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
        _ = manager
        distribute(inputs: inputs, destinationRoot: distributionRootDirectory, shouldSynchronizeLatestSession: true)
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

    func undoLastDistribution() {
        guard !isBusy else { return }

        let undoItems = postProcessedItems.filter { $0.originalPath != $0.currentPath }
        guard !undoItems.isEmpty else {
            postProcessingSummary = "Нет переноса для отмены."
            appendLog("Отмена переноса пропущена: нет последнего переноса.")
            return
        }

        let manager = FileManager.default
        var restoredItems: [PostProcessedItem] = []
        var failedItems: [PostProcessedItem] = []
        var latestUpdates = Dictionary(uniqueKeysWithValues: latestSessionDownloadedItems.map { ($0.id, $0) })
        var failedPaths: [String] = []

        for item in undoItems.reversed() {
            let currentURL = URL(fileURLWithPath: item.currentPath)
            let originalURL = URL(fileURLWithPath: item.originalPath)

            guard manager.fileExists(atPath: currentURL.path) else {
                failedPaths.append(currentURL.lastPathComponent)
                failedItems.append(item)
                appendLog("Файл не найден для отмены переноса: \(currentURL.path).")
                continue
            }

            do {
                try manager.createDirectory(
                    at: originalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                let restoredURL = manager.fileExists(atPath: originalURL.path)
                    && currentURL.standardizedFileURL != originalURL.standardizedFileURL
                    ? uniqueDestinationURL(
                        for: originalURL.lastPathComponent,
                        in: originalURL.deletingLastPathComponent(),
                        fileManager: manager
                    )
                    : originalURL

                if currentURL.standardizedFileURL != restoredURL.standardizedFileURL {
                    try manager.moveItem(at: currentURL, to: restoredURL)
                }

                let restored = PostProcessedItem(
                    id: item.id,
                    originalUsername: item.originalUsername,
                    targetFolderName: item.targetFolderName,
                    originalPath: item.currentPath,
                    currentPath: restoredURL.path
                )
                restoredItems.append(restored)

                if let latestItem = latestUpdates[item.id] {
                    latestUpdates[item.id] = latestItem.with(localPath: restoredURL.path)
                }
            } catch {
                failedPaths.append(currentURL.lastPathComponent)
                failedItems.append(item)
                appendLog("Не удалось отменить перенос \(currentURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        latestSessionDownloadedItems = latestSessionDownloadedItems.map { latestUpdates[$0.id] ?? $0 }
        synchronizeDownloadedItems(with: latestSessionDownloadedItems)
        googleDriveLinkSummary = "Перенос отменён. После новой сортировки Drive-ссылки нужно собрать заново."

        if failedPaths.isEmpty {
            postProcessedItems = []
            postProcessingSummary = "Отменён перенос файлов: \(restoredItems.count)."
        } else {
            postProcessedItems = failedItems
            postProcessingSummary = "Отменён перенос файлов: \(restoredItems.count). Ошибок: \(failedPaths.count)."
            appendLog("Не удалось вернуть файлов: \(failedPaths.joined(separator: ", ")).")
        }
        appendLog(postProcessingSummary)
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
        !postProcessedItems.isEmpty
            ? postProcessedItems
            : latestSessionDownloadedItems.map {
                let username = sourceUsername(for: $0)
                return PostProcessedItem(
                    id: $0.id,
                    originalUsername: username,
                    targetFolderName: username,
                    originalPath: resolvedCurrentURL(for: $0).path,
                    currentPath: resolvedCurrentURL(for: $0).path
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

        let recordsByID = Dictionary(uniqueKeysWithValues: currentPostProcessingRecords().map { ($0.id, $0) })
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
        guard let mapped = mapping[username.lowercased()]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mapped.isEmpty
        else {
            return username
        }

        let sanitized = mapped
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sanitized.isEmpty else { return username }

        if sanitized.count == 1 {
            return sanitized[0] + "/" + username
        }

        return sanitized.joined(separator: "/")
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

        let existing = Dictionary(uniqueKeysWithValues: rememberedBloggers.map { ($0.id, $0) })
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

        var merged = Dictionary(uniqueKeysWithValues: rememberedBloggers.map { ($0.id, $0) })
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
        rememberedBloggers = decoded.sorted {
            if $0.countryFolder == $1.countryFolder {
                return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
            }
            return $0.countryFolder.localizedCaseInsensitiveCompare($1.countryFolder) == .orderedAscending
        }
    }

    @discardableResult
    func refreshNotionRoutingRules() async -> Bool {
        guard !isBusy, !isRefreshingNotionRoutingRules else { return false }

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

    private func uniqueDestinationURL(for filename: String, in directory: URL, fileManager: FileManager) -> URL {
        let candidate = directory.appendingPathComponent(filename, isDirectory: false)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        let numberedName = splitTrailingNumber(from: stem)
        var index = numberedName.nextNumber

        while true {
            let adjustedStem = numberedName.prefix + formattedNumber(index, width: numberedName.width)
            let adjustedName = ext.isEmpty ? adjustedStem : "\(adjustedStem).\(ext)"
            let adjustedURL = directory.appendingPathComponent(adjustedName, isDirectory: false)
            if !fileManager.fileExists(atPath: adjustedURL.path) {
                return adjustedURL
            }
            index += 1
        }
    }

    private func splitTrailingNumber(from stem: String) -> (prefix: String, nextNumber: Int, width: Int) {
        guard let range = stem.range(of: #"\d+$"#, options: .regularExpression) else {
            return ("\(stem) ", 2, 0)
        }

        let numberText = String(stem[range])
        let prefix = String(stem[..<range.lowerBound])
        return (prefix, (Int(numberText) ?? 1) + 1, numberText.count)
    }

    private func formattedNumber(_ number: Int, width: Int) -> String {
        guard width > 0 else { return "\(number)" }
        return String(format: "%0\(width)d", number)
    }

    private func synchronizeDownloadedItems(with updatedItems: [WorkerItem]) {
        let updatedMap = Dictionary(uniqueKeysWithValues: updatedItems.map { ($0.id, $0) })
        downloadedItems = downloadedItems.map { item in
            updatedMap[item.id] ?? item
        }
    }

    private func distribute(
        inputs: [FileDistributionInput],
        destinationRoot: URL,
        shouldSynchronizeLatestSession: Bool
    ) {
        let manager = FileManager.default
        var latestUpdates = Dictionary(uniqueKeysWithValues: latestSessionDownloadedItems.map { ($0.id, $0) })
        var movedRecords: [PostProcessedItem] = []
        var movedCount = 0
        var failedPaths: [String] = []

        do {
            try manager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        } catch {
            postProcessingSummary = "Не удалось подготовить папку назначения: \(error.localizedDescription)"
            appendLog(postProcessingSummary)
            return
        }

        for input in inputs {
            guard manager.fileExists(atPath: input.currentURL.path) else {
                failedPaths.append(input.currentURL.lastPathComponent)
                appendLog("Файл не найден для сортировки: \(input.currentURL.path).")
                continue
            }

            let destinationDirectory = destinationRoot.appendingPathComponent(input.targetRelativeFolder, isDirectory: true)

            do {
                try manager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                let destinationURL = uniqueDestinationURL(
                    for: input.currentURL.lastPathComponent,
                    in: destinationDirectory,
                    fileManager: manager
                )

                if input.currentURL.standardizedFileURL != destinationURL.standardizedFileURL {
                    try manager.moveItem(at: input.currentURL, to: destinationURL)
                    movedCount += 1
                }

                movedRecords.append(
                    PostProcessedItem(
                        id: input.id,
                        originalUsername: input.originalUsername,
                        targetFolderName: input.targetRelativeFolder,
                        originalPath: input.currentURL.path,
                        currentPath: destinationURL.path
                    )
                )

                if shouldSynchronizeLatestSession, let latestItem = latestUpdates[input.id] {
                    latestUpdates[input.id] = latestItem.with(localPath: destinationURL.path)
                }
            } catch {
                failedPaths.append(input.currentURL.lastPathComponent)
                appendLog("Не удалось переложить \(input.currentURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if shouldSynchronizeLatestSession {
            latestSessionDownloadedItems = latestSessionDownloadedItems.map { latestUpdates[$0.id] ?? $0 }
            synchronizeDownloadedItems(with: latestSessionDownloadedItems)
        }

        postProcessedItems = movedRecords.sorted {
            if $0.targetFolderName == $1.targetFolderName {
                return $0.currentPath.localizedStandardCompare($1.currentPath) == .orderedAscending
            }
            return $0.targetFolderName.localizedCaseInsensitiveCompare($1.targetFolderName) == .orderedAscending
        }
        rememberBloggers(from: postProcessedItems)

        if movedCount > 0 {
            postProcessingSummary = "Разложено файлов: \(movedCount). Подпапок затронуто: \(Set(movedRecords.map(\.targetFolderName)).count)."
            appendLog(postProcessingSummary)
        } else if !failedPaths.isEmpty {
            postProcessingSummary = "Не удалось разложить файлы: \(failedPaths.count)."
        } else {
            postProcessingSummary = "Файлы уже лежат в нужных папках."
        }

        if !failedPaths.isEmpty {
            appendLog("Не удалось обработать файлов: \(failedPaths.joined(separator: ", ")).")
        }
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

private struct FileDistributionInput {
    let id: String
    let originalUsername: String
    let currentURL: URL
    let targetRelativeFolder: String
}
