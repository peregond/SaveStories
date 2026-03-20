import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter
    }()

    private struct BatchWorkerResult: Decodable {
        let url: String
        let status: String
        let message: String
        let foundCount: Int
        let savedCount: Int
    }

    struct BatchProfileItem: Identifiable, Hashable {
        enum Status: String {
            case pending
            case running
            case completed
            case failed
            case stopped

            var title: String {
                switch self {
                case .pending:
                    "В очереди"
                case .running:
                    "Скачивается"
                case .completed:
                    "Готово"
                case .failed:
                    "Ошибка"
                case .stopped:
                    "Остановлено"
                }
            }
        }

        let id: UUID
        var url: String
        var status: Status
        var message: String

        init(id: UUID = UUID(), url: String, status: Status = .pending, message: String = "Ожидает запуска.") {
            self.id = id
            self.url = url
            self.status = status
            self.message = message
        }
    }

    enum DownloadMode: String, CaseIterable, Identifiable {
        case background
        case visible

        var id: String { rawValue }

        var title: String {
            switch self {
            case .background:
                "В фоне"
            case .visible:
                "Видимо"
            }
        }

        var detail: String {
            switch self {
            case .background:
                "Браузер не показывается во время выгрузки."
            case .visible:
                "Открывает окно Chromium во время выгрузки."
            }
        }

        var usesHeadless: Bool {
            switch self {
            case .background:
                true
            case .visible:
                false
            }
        }
    }

    @Published var profileURL: String = ""
    @Published var batchInput: String = ""
    @Published var batchQueue: [BatchProfileItem] = []
    @Published var downloadMode: DownloadMode = .background
    @Published var saveDirectory: URL = AppPaths.defaultDownloads
    @Published var workerSummary: String = "Воркер ещё не проверялся."
    @Published var sessionSummary: String = "Состояние сессии неизвестно."
    @Published var lastResult: String = "Действий пока не было."
    @Published var statusTitle: String = "Ожидание"
    @Published var statusDetail: String = "Приложение готово к работе."
    @Published var currentStepLabel: String = "Ожидание команды."
    @Published var foundStoriesCount: Int = 0
    @Published var savedStoriesCount: Int = 0
    @Published var runtimeSummary: String = ""
    @Published var downloadedItems: [WorkerItem] = []
    @Published var logs: [String] = []
    @Published var isBusy = false
    @Published var workerReady = false
    @Published var sessionReady = false
    @Published var showLoginPrompt = false
    @Published var batchIsRunning = false
    @Published var batchStopRequested = false
    @Published var batchCurrentIndex = 0
    @Published var batchTotalCount = 0
    @Published var batchRemainingCount = 0
    @Published var batchCurrentURL: String = ""

    private let worker = WorkerClient()
    private let bootstrapper = WorkerBootstrapper()
    private var hasPrepared = false
    var hasEmbeddedRuntime: Bool { AppPaths.hasEmbeddedRuntime }

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        do {
            try AppPaths.ensureDirectories()
            saveDirectory = AppPaths.defaultDownloads
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
                WorkerRequest(command: "login", url: nil, urls: nil, outputDirectory: self.saveDirectory.path, headless: false)
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
                WorkerRequest(command: "check_session", url: nil, urls: nil, outputDirectory: nil, headless: true)
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

    func runBatchDownloads() async {
        let pendingItems = batchQueue.filter { $0.status == .pending || $0.status == .failed }
        guard !pendingItems.isEmpty else {
            appendLog("В очереди нет ссылок для пакетной выгрузки.")
            return
        }

        await perform("Пакетная выгрузка активных stories") {
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
                    headless: self.downloadMode.usesHeadless
                )
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
            self.batchRemainingCount = 0
            self.batchCurrentURL = ""
            self.batchCurrentIndex = 0
            self.batchIsRunning = false
            self.batchStopRequested = false
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

    func openSaveDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([saveDirectory])
    }

    func openRuntimeDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.applicationSupport])
    }

    private func perform(_ message: String, task: @escaping @MainActor () async -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        statusTitle = message
        statusDetail = "Выполняется..."
        currentStepLabel = "Запускаю задачу."
        if message.contains("Скачивание") {
            foundStoriesCount = 0
            savedStoriesCount = 0
        }
        appendLog(message)
        await task()
        isBusy = false
        if statusTitle == "Готово" {
            currentStepLabel = "Операция завершена."
        } else if statusTitle == "Ошибка" {
            currentStepLabel = "Операция завершилась ошибкой."
        }
        if !batchIsRunning {
            batchCurrentURL = ""
        }
    }

    private func runProfileDownload(for url: String) async -> WorkerResponse {
        await worker.run(
            WorkerRequest(
                command: "download_profile_stories",
                url: normalizedProfileLink(url),
                urls: nil,
                outputDirectory: saveDirectory.path,
                headless: downloadMode.usesHeadless
            )
        )
    }

    private func append(_ response: WorkerResponse) {
        if !response.items.isEmpty {
            downloadedItems = response.items + downloadedItems
        }

        if let found = Int(response.data["foundCount"] ?? "") {
            foundStoriesCount = found
        } else if response.status == "download_complete" || response.status == "download_empty" {
            foundStoriesCount = response.items.count
        }

        if let saved = Int(response.data["savedCount"] ?? "") {
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
        appendLog("[\(response.status)] \(response.message)")

        for log in response.logs {
            updateCurrentStep(from: log)
            appendLog(log)
        }
    }

    private func environmentResponse() async -> WorkerResponse {
        await worker.run(WorkerRequest(command: "environment", url: nil, urls: nil, outputDirectory: nil, headless: nil))
    }

    private func refreshStartupSession() async {
        let response = await worker.run(
            WorkerRequest(command: "check_session", url: nil, urls: nil, outputDirectory: nil, headless: true)
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
        let runtimeMode = AppPaths.hasEmbeddedRuntime ? "embedded" : "external"
        return """
        mode=\(runtimeMode)
        runtime=\(AppPaths.applicationSupport.path)
        worker_runtime=\(runtimeKind)
        executable=\(runtimeExecutable)
        profile=\(profile)
        browsers=\(browsers)
        manifests=\(manifests)
        """
    }

    private func parsedBatchLinks(from input: String) -> [String] {
        input
            .split(whereSeparator: \.isNewline)
            .flatMap { chunk in
                chunk.split(separator: ",")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedProfileLink(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.contains("instagram.com") {
            return trimmed
        }

        let username = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
        return "https://www.instagram.com/\(username)/"
    }

    private func updateBatchProfile(id: UUID, status: BatchProfileItem.Status, message: String) {
        guard let index = batchQueue.firstIndex(where: { $0.id == id }) else { return }
        batchQueue[index].status = status
        batchQueue[index].message = message
    }

    private func applyBatchResults(_ response: WorkerResponse, pendingItems: [BatchProfileItem]) {
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

    private func resetBatchProgress() {
        batchIsRunning = false
        batchStopRequested = false
        batchCurrentIndex = 0
        batchTotalCount = 0
        batchRemainingCount = 0
        batchCurrentURL = ""
    }

    private func appendLog(_ message: String) {
        logs.insert("\(Self.logDateFormatter.string(from: Date()))  \(message)", at: 0)
    }

    private func updateCurrentStep(from log: String) {
        let lowered = log.lowercased()

        if lowered.contains("batch_concurrency=") {
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
    }
}
