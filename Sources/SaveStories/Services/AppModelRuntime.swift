import AppKit
import Foundation

extension AppModel {
    static let sleepPreventionActivityOptions: ProcessInfo.ActivityOptions = [
        .idleSystemSleepDisabled,
        .idleDisplaySleepDisabled
    ]

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        do {
            try AppPaths.ensureDirectories()
            try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
            resetLiveDownloadTrackingBaseline()
            appendLog("Подготовлены папки приложения в \(AppPaths.applicationSupport.path).")
        } catch {
            appendLog("Не удалось подготовить папки: \(error.localizedDescription)")
        }

        await refreshEnvironment()
        if workerReady {
            await refreshStartupSession()
        }
    }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canCreateDirectories = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Выбрать"
        panel.directoryURL = saveDirectory

        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url
            UserDefaults.standard.set(url.path, forKey: Self.saveDirectoryKey)
            resetLiveDownloadTrackingBaseline()
            appendLog("Папка сохранения изменена на \(url.path).")
        }
    }

    func refreshEnvironment() async {
        await perform("Проверка среды воркера") {
            self.currentStepLabel = "Проверяю состояние среды воркера."
            let response = await self.environmentResponse()
            self.applyEnvironment(response)
            self.append(response)
        }
    }

    func bootstrapEnvironment() async {
        await perform("Подготовка среды воркера") {
            do {
                let output = try await self.bootstrapper.run()
                output
                    .split(separator: "\n")
                    .map(String.init)
                    .filter { !$0.isEmpty }
                    .forEach { self.appendLog($0) }

                let response = await self.environmentResponse()
                self.applyEnvironment(response)
                self.append(response)
            } catch {
                self.workerReady = false
                self.statusTitle = "Ошибка"
                self.statusDetail = error.localizedDescription
                self.lastResult = error.localizedDescription
                self.appendLog(error.localizedDescription)
            }
        }
    }

    func login() async {
        showLoginPrompt = false
        await perform("Открытие видимого браузера для входа в Instagram") {
            self.currentStepLabel = "Открываю браузер для входа в Instagram."
            let response = await self.worker.run(
                WorkerRequest(command: "login", url: nil, urls: nil, outputDirectory: self.saveDirectory.path, headless: false, mediaFilter: nil)
            )
            if response.ok {
                self.sessionReady = response.data["loggedIn"] == "true"
                self.sessionSummary = response.message
                self.showLoginPrompt = !self.sessionReady
            } else {
                self.sessionReady = false
                self.sessionSummary = response.message
                self.showLoginPrompt = true
            }
            self.append(response)
        }
    }

    func checkSession() async {
        await perform("Проверка сохранённой сессии Instagram") {
            self.currentStepLabel = "Проверяю сохранённую Instagram-сессию."
            let response = await self.worker.run(
                WorkerRequest(command: "check_session", url: nil, urls: nil, outputDirectory: nil, headless: true, mediaFilter: nil)
            )
            if response.ok {
                self.sessionReady = response.data["loggedIn"] == "true"
                self.sessionSummary = response.message
                self.showLoginPrompt = !self.sessionReady
            } else {
                self.sessionReady = false
                self.sessionSummary = response.message
                self.showLoginPrompt = false
            }
            self.append(response)
        }
    }

    func dismissLoginPrompt() {
        showLoginPrompt = false
    }

    func downloadProfileStories() async {
        let trimmed = profileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appendLog("Ссылка на профиль пустая.")
            return
        }

        await perform("Скачивание активных stories из профиля") {
            let response = await self.runProfileDownload(for: trimmed)
            self.append(response)
        }
    }

    func downloadReels() async {
        let urls = parsedReelLinks(from: reelsInput)
        guard !urls.isEmpty else {
            appendLog("Не найдено ни одной ссылки на Reels.")
            return
        }

        await perform("Скачивание Reels") {
            self.currentStepLabel = "Открываю ссылку на Reels и подготавливаю выгрузку."
            let response = await self.worker.run(
                WorkerRequest(
                    command: "download_reels_urls",
                    url: nil,
                    urls: urls,
                    outputDirectory: self.saveDirectory.path,
                    headless: self.downloadMode.usesHeadless,
                    mediaFilter: nil
                )
            )
            if response.ok {
                self.reelsInput = ""
            }
            self.append(response)
        }
    }

    func perform(_ message: String, task: @escaping @MainActor () async -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        statusTitle = message
        statusDetail = "Выполняется..."
        currentStepLabel = "Запускаю задачу."
        let normalizedMessage = message.lowercased()
        let isDownloadOperation = normalizedMessage.contains("скачив") || normalizedMessage.contains("выгруз")
        if isDownloadOperation {
            foundStoriesCount = 0
            savedStoriesCount = 0
            latestSessionDownloadedItems = []
            postProcessedItems = []
            postProcessingSummary = "Идёт новая выгрузка. После неё можно будет разложить файлы."
            isDownloadActivityInProgress = true
            refreshSleepPreventionForCurrentState()
            beginLiveDownloadTracking()
        }

        defer {
            isBusy = false
            stopLiveDownloadTracking()
            if isDownloadOperation {
                isDownloadActivityInProgress = false
                refreshSleepPreventionForCurrentState()
            }
            refreshLiveDownloadTracking()
            if statusTitle == "Готово" {
                currentStepLabel = "Операция завершена."
            } else if statusTitle == "Ошибка" {
                currentStepLabel = "Операция завершилась ошибкой."
            }
            if !batchIsRunning {
                batchCurrentURL = ""
            }
        }

        appendLog(message)
        await task()
    }

    func append(_ response: WorkerResponse) {
        if !response.items.isEmpty {
            downloadedItems = response.items + downloadedItems
            if isDownloadActivityInProgress {
                let existingIDs = Set(latestSessionDownloadedItems.map(\.id))
                let freshItems = response.items.filter { !existingIDs.contains($0.id) }
                if !freshItems.isEmpty {
                    latestSessionDownloadedItems.append(contentsOf: freshItems)
                }
            }
        }

        if let found = response.counts?.found ?? Int(response.data["foundCount"] ?? "") {
            foundStoriesCount = found
        } else if response.status == "download_complete" || response.status == "download_empty" {
            foundStoriesCount = response.items.count
        }

        if let saved = response.counts?.saved ?? Int(response.data["savedCount"] ?? "") {
            savedStoriesCount = saved
        } else if response.status == "download_complete" {
            savedStoriesCount = response.items.count
        }

        if response.status == "cancelled" {
            statusTitle = "Остановлено"
        } else {
            statusTitle = response.ok ? "Готово" : "Ошибка"
        }
        statusDetail = response.message
        lastResult = response.message
        currentStepLabel = response.ok ? "Обработка завершена." : "Обработка завершилась ошибкой."
        if response.ok && savedStoriesCount > 0 && response.status == "download_complete" {
            triggerCelebration()
        }
        appendLog("[\(response.status)] \(response.message)")

        for log in response.logs {
            updateCurrentStep(from: log)
            appendLog(log)
        }
    }

    func handleWorkerProgress(_ line: String) {
        updateCurrentStep(from: line)
    }

    private func runProfileDownload(for url: String) async -> WorkerResponse {
        await worker.run(
            WorkerRequest(
                command: "download_profile_stories",
                url: normalizedProfileLink(url),
                urls: nil,
                outputDirectory: saveDirectory.path,
                headless: downloadMode.usesHeadless,
                mediaFilter: mediaSelectionMode.rawValue
            )
        )
    }

    private func environmentResponse() async -> WorkerResponse {
        await worker.run(WorkerRequest(command: "environment", url: nil, urls: nil, outputDirectory: nil, headless: nil, mediaFilter: nil))
    }

    func parsedReelLinks(from input: String) -> [String] {
        input
            .split(whereSeparator: \.isNewline)
            .flatMap { chunk in
                chunk.split(separator: ",")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(normalizedReelLink(_:))
    }

    func normalizedReelLink(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return nil
        }
        guard host.contains("instagram.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let kind = parts[0].lowercased()
        guard kind == "reel" || kind == "reels" || kind == "p" else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        components?.path = "/\(kind)/\(parts[1])/"
        return components?.url?.absoluteString
    }

    private func refreshStartupSession() async {
        let response = await worker.run(
            WorkerRequest(command: "check_session", url: nil, urls: nil, outputDirectory: nil, headless: true, mediaFilter: nil)
        )
        if response.ok {
            sessionReady = response.data["loggedIn"] == "true"
            sessionSummary = response.message
            showLoginPrompt = !sessionReady
        } else {
            sessionReady = false
            sessionSummary = response.message
            showLoginPrompt = true
        }
        append(response)

        if !sessionReady {
            statusTitle = "Нужен вход"
            statusDetail = "Для работы приложения сначала войди в Instagram через встроенный браузер."
            lastResult = statusDetail
            currentStepLabel = "Ожидаю вход в Instagram."
        }
    }

    private func applyEnvironment(_ response: WorkerResponse) {
        workerReady = response.ok
        workerSummary = response.message
        runtimeSummary = buildRuntimeSummary(from: response)
    }

    private func buildRuntimeSummary(from response: WorkerResponse) -> String {
        let runtimeExecutable = response.data["node"] ?? response.data["python"] ?? "unknown"
        let runtimeKind = response.data["runtime"] ?? "node"
        let profile = response.data["browserProfile"] ?? AppPaths.browserProfile.path
        let browsers = response.data["playwrightBrowsers"] ?? AppPaths.playwrightBrowsers.path
        let manifests = response.data["manifests"] ?? AppPaths.manifestsDirectory.path
        let logs = response.data["logsDirectory"] ?? AppPaths.logsDirectory.path
        let health = response.data["health"] ?? "[]"
        let runtimeMode = AppPaths.hasEmbeddedRuntime ? "embedded" : "external"
        return """
        mode=\(runtimeMode)
        runtime=\(AppPaths.applicationSupport.path)
        worker_runtime=\(runtimeKind)
        executable=\(runtimeExecutable)
        profile=\(profile)
        browsers=\(browsers)
        manifests=\(manifests)
        logs=\(logs)
        health=\(health)
        """
    }

    private func updateCurrentStep(from log: String) {
        let lowered = log.lowercased()

        if lowered.contains("batch_profile_start=") || lowered.contains("batch_slot_") && lowered.contains("_start=") {
            let url = log.components(separatedBy: "=").dropFirst().joined(separator: "=")
            let normalized = normalizedProfileLink(url)
            let username = extractProgressDisplayName(from: normalized)
            let completedCount = batchQueue.filter { item in
                item.status == .completed || item.status == .failed || item.status == .stopped
            }.count
            batchCurrentIndex = min(completedCount + 1, max(batchTotalCount, 1))
            batchRemainingCount = max(batchTotalCount - batchCurrentIndex, 0)
            batchCurrentURL = normalized
            currentStepLabel = "Открываю профиль \(username)."
        } else if lowered.contains("batch_profile_done=") || lowered.contains("batch_slot_") && lowered.contains("_done=") {
            let url = log.components(separatedBy: "=").dropFirst().joined(separator: "=")
            let normalized = normalizedProfileLink(url)
            let username = extractProgressDisplayName(from: normalized)
            currentStepLabel = "Профиль \(username) обработан, переключаюсь дальше."
        } else if lowered.contains("batch_concurrency=") {
            currentStepLabel = "Распределяю очередь по активным слотам."
        } else if lowered.contains("opened=") || lowered.contains("checked=") {
            currentStepLabel = "Открываю страницу Instagram."
        } else if lowered.contains("opened_active_story") || lowered.contains("story_viewer") {
            currentStepLabel = "Открываю stories viewer."
        } else if lowered.contains("storage_state_saved=") {
            currentStepLabel = "Сохраняю браузерную сессию."
        } else if lowered.contains("saved=") {
            currentStepLabel = "Сохраняю файл на диск."
        } else if lowered.contains("manifest=") {
            currentStepLabel = "Записываю метаданные загрузки."
        } else if lowered.contains("background_window") {
            currentStepLabel = "Подготавливаю фоновый режим браузера."
        } else if lowered.contains("playwright=") || lowered.contains("worker_runtime=") {
            currentStepLabel = "Проверяю runtime и зависимости."
        }

        if lowered.contains("saved=") || lowered.contains("profile_download_directory=") {
            refreshLiveDownloadTracking()
        }
    }

    private func extractProgressDisplayName(from normalizedURL: String) -> String {
        normalizedURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .last
            .map(String.init) ?? normalizedURL
    }

    private func beginLiveDownloadTracking() {
        resetLiveDownloadTrackingBaseline()
        liveTrackingTask?.cancel()
        liveTrackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                let saveDirectory = self.saveDirectory
                let baselineFiles = self.saveDirectoryBaselineFiles
                let baselineFolders = self.saveDirectoryBaselineFolders
                let snapshot = await Task.detached(priority: .utility) {
                    Self.snapshot(of: saveDirectory)
                }.value
                await MainActor.run {
                    self.liveDownloadedFileCount = max(snapshot.files - baselineFiles, 0)
                    self.liveCreatedFolderCount = max(snapshot.folders - baselineFolders, 0)
                }
            }
        }
    }

    private func refreshLiveDownloadTracking() {
        let snapshot = Self.snapshot(of: saveDirectory)
        liveDownloadedFileCount = max(snapshot.files - saveDirectoryBaselineFiles, 0)
        liveCreatedFolderCount = max(snapshot.folders - saveDirectoryBaselineFolders, 0)
    }

    private func resetLiveDownloadTrackingBaseline() {
        let snapshot = Self.snapshot(of: saveDirectory)
        saveDirectoryBaselineFiles = snapshot.files
        saveDirectoryBaselineFolders = snapshot.folders
        liveDownloadedFileCount = 0
        liveCreatedFolderCount = 0
    }

    private func stopLiveDownloadTracking() {
        liveTrackingTask?.cancel()
        liveTrackingTask = nil
    }

    func refreshSleepPreventionForCurrentState() {
        if preventSleepDuringDownloads && isDownloadActivityInProgress {
            beginSleepPrevention()
        } else {
            endSleepPrevention()
        }
    }

    private func beginSleepPrevention() {
        guard sleepPreventionActivity == nil else { return }
        sleepPreventionActivity = ProcessInfo.processInfo.beginActivity(
            options: Self.sleepPreventionActivityOptions,
            reason: "SaveMe download in progress"
        )
    }

    private func endSleepPrevention() {
        guard let activity = sleepPreventionActivity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        sleepPreventionActivity = nil
    }

    nonisolated private static func snapshot(of directory: URL) -> (files: Int, folders: Int) {
        let fileManager = FileManager.default
        var fileCount = 0
        var folderCount = 0
        let supportedExtensions = Set(["jpg", "jpeg", "png", "webp", "mp4", "mov", "m4v"])

        if let directChildren = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in directChildren {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    folderCount += 1
                }
            }
        }

        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == false && supportedExtensions.contains(url.pathExtension.lowercased()) {
                    fileCount += 1
                }
            }
        }

        return (fileCount, folderCount)
    }
}
