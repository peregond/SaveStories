import AppKit
import Foundation

extension AppModel {
    func chooseSortingSourceDirectory() {
        let panel = NSOpenPanel()
        panel.canCreateDirectories = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Выбрать"
        panel.directoryURL = sortingSourceDirectory ?? saveDirectory

        if panel.runModal() == .OK, let url = panel.url {
            sortingSourceDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.sortingSourceDirectoryKey)
            postProcessingSummary = "Источник сортировки выбран: \(url.lastPathComponent)."
            appendLog("Папка источника сортировки изменена на \(url.path).")
        }
    }

    func openSortingSourceDirectory() {
        guard let sortingSourceDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([sortingSourceDirectory])
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

            let report = self.buildGoogleDriveLinkReport(from: outcomes)
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
        let panel = NSOpenPanel()
        panel.canCreateDirectories = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Выбрать"
        panel.directoryURL = distributionRootDirectory ?? saveDirectory

        if panel.runModal() == .OK, let url = panel.url {
            distributionRootDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.distributionRootDirectoryKey)
            postProcessingSummary = "Папка раскладки выбрана: \(url.lastPathComponent)."
            appendLog("Папка раскладки изменена на \(url.path).")
        }
    }

    func openDistributionRootDirectory() {
        guard let distributionRootDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([distributionRootDirectory])
    }

    func distributeFilesFromSortingSource() {
        guard !isBusy else { return }
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

    func parsedFolderRoutingRules() -> [String: String] {
        folderRoutingRules
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

    private func targetRelativeFolderPath(for username: String, mapping: [String: String]) -> String {
        let mapped = mapping[username.lowercased()]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (mapped?.isEmpty == false ? mapped! : username)
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
        var index = 2

        while true {
            let suffix = " \(index)"
            let adjustedName = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
            let adjustedURL = directory.appendingPathComponent(adjustedName, isDirectory: false)
            if !fileManager.fileExists(atPath: adjustedURL.path) {
                return adjustedURL
            }
            index += 1
        }
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
