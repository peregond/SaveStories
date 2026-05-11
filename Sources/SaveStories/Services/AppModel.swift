import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let recentBatchListsKey = "SaveStories.recentBatchLists"
    private static let mediaSelectionModeKey = "SaveStories.mediaSelectionMode"
    static let saveDirectoryKey = "SaveStories.saveDirectory"
    static let distributionRootDirectoryKey = "SaveStories.distributionRootDirectory"
    static let sortingSourceDirectoryKey = "SaveStories.sortingSourceDirectory"
    static let folderRoutingRulesKey = "SaveStories.folderRoutingRules"
    static let rememberedBloggersKey = "SaveStories.rememberedBloggers"
    private static let preventSleepDuringDownloadsKey = "SaveStories.preventSleepDuringDownloads"
    static let runtimeOnboardingDismissedKey = "SaveStories.runtimeOnboardingDismissed"
    private static let actionSoundNames = ["Pop", "Tink", "Glass"]
    private static let successSoundNames = ["Glass", "Hero", "Funk", "Pop"]
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter
    }()

    typealias BatchWorkerResult = WorkerBatchResult

    struct RecentBatchList: Identifiable, Codable, Hashable {
        let id: UUID
        var title: String
        var urls: [String]
        var createdAt: Date

        init(id: UUID = UUID(), title: String, urls: [String], createdAt: Date = Date()) {
            self.id = id
            self.title = title
            self.urls = urls
            self.createdAt = createdAt
        }

        var subtitle: String {
            "\(urls.count) профилей"
        }
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

    struct EmptyFolderCleanupReport: Identifiable {
        let id = UUID()
        let removedCount: Int
        let folderNames: [String]

        var title: String {
            removedCount > 0 ? "Пустые папки удалены" : "Удалять нечего"
        }

        var message: String {
            guard removedCount > 0 else {
                return "После проверки пустых папок для удаления не осталось."
            }

            let preview = folderNames.prefix(5).joined(separator: "\n")
            if folderNames.count > 5 {
                return "Удалено пустых папок: \(removedCount).\n\n\(preview)\nи ещё \(folderNames.count - 5)."
            }
            return "Удалено пустых папок: \(removedCount).\n\n\(preview)"
        }
    }

    struct PostProcessedItem: Identifiable, Hashable {
        let id: String
        let originalUsername: String
        let targetFolderName: String
        let currentPath: String

        var reportHeader: String {
            if targetFolderName.caseInsensitiveCompare(originalUsername) == .orderedSame {
                return "[\(targetFolderName)]"
            }
            return "[\(targetFolderName) (\(originalUsername))]"
        }
    }

    struct RememberedBlogger: Identifiable, Codable, Hashable {
        var id: String { username.lowercased() }
        let username: String
        var countryFolder: String
        var targetFolder: String
        var lastUsedAt: Date
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

    enum MediaSelectionMode: String, CaseIterable, Identifiable {
        case all
        case videoOnly = "video_only"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                "Фото и видео"
            case .videoOnly:
                "Только видео"
            }
        }

        var detail: String {
            switch self {
            case .all:
                "Сохраняет все найденные stories: и фото, и видео."
            case .videoOnly:
                "Сохраняет только видео-stories. Фото будут пропущены."
            }
        }
    }

    enum RuntimeSetupStage: String, CaseIterable, Identifiable {
        case welcome
        case folders
        case node
        case worker
        case packages
        case browser
        case ready
        case failed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .welcome:
                "Подготовка"
            case .folders:
                "Папки приложения"
            case .node:
                "Node 24 LTS"
            case .worker:
                "Worker"
            case .packages:
                "Playwright"
            case .browser:
                "Chromium"
            case .ready:
                "Готово"
            case .failed:
                "Нужно повторить"
            }
        }

        var detail: String {
            switch self {
            case .welcome:
                "Сейчас приложение докачает компоненты для работы."
            case .folders:
                "Готовим локальное хранилище."
            case .node:
                "Проверяем или скачиваем Node."
            case .worker:
                "Копируем рабочий модуль."
            case .packages:
                "Ставим зависимости."
            case .browser:
                "Скачиваем браузер для выгрузки."
            case .ready:
                "Движок установлен."
            case .failed:
                "Установка не завершилась."
            }
        }
    }

    @Published var profileURL: String = ""
    @Published var batchInput: String = ""
    @Published var reelsInput: String = ""
    @Published var batchQueue: [BatchProfileItem] = []
    @Published var downloadMode: DownloadMode = .background
    @Published var mediaSelectionMode: MediaSelectionMode = .videoOnly {
        didSet {
            UserDefaults.standard.set(mediaSelectionMode.rawValue, forKey: Self.mediaSelectionModeKey)
        }
    }
    @Published var preventSleepDuringDownloads = true {
        didSet {
            UserDefaults.standard.set(preventSleepDuringDownloads, forKey: Self.preventSleepDuringDownloadsKey)
            refreshSleepPreventionForCurrentState()
        }
    }
    @Published var saveDirectory: URL = AppPaths.defaultDownloads
    @Published var distributionRootDirectory: URL?
    @Published var sortingSourceDirectory: URL?
    @Published var folderRoutingRules: String = "" {
        didSet {
            UserDefaults.standard.set(folderRoutingRules, forKey: Self.folderRoutingRulesKey)
        }
    }
    @Published var workerSummary: String = "Воркер ещё не проверялся."
    @Published var sessionSummary: String = "Состояние сессии неизвестно."
    @Published var lastResult: String = "Действий пока не было."
    @Published var statusTitle: String = "Ожидание"
    @Published var statusDetail: String = "Приложение готово к работе."
    @Published var currentStepLabel: String = "Ожидание команды."
    @Published var foundStoriesCount: Int = 0
    @Published var savedStoriesCount: Int = 0
    @Published var runtimeSummary: String = ""
    @Published var updateSummary: String = "Автообновление ещё не настроено для этой сборки."
    @Published var canCheckForUpdates = false
    @Published var isCheckingForUpdates = false
    @Published var downloadedItems: [WorkerItem] = []
    @Published var logs: [String] = []
    @Published var isBusy = false
    @Published var workerReady = false
    @Published var sessionReady = false
    @Published var showLoginPrompt = false
    @Published var showRuntimeOnboarding = false
    @Published var runtimeSetupStage: RuntimeSetupStage = .welcome
    @Published var runtimeSetupFailedStage: RuntimeSetupStage?
    @Published var runtimeSetupMessage = "Подготовим движок, без которого приложение не сможет скачивать stories."
    @Published var runtimeSetupErrorMessage: String?
    @Published var showEmptyFolderCleanupPrompt = false
    @Published var emptyFolderCleanupReport: EmptyFolderCleanupReport?
    @Published var recentBatchLists: [RecentBatchList] = []
    @Published var batchIsRunning = false
    @Published var batchStopRequested = false
    @Published var batchCurrentIndex = 0
    @Published var batchTotalCount = 0
    @Published var batchRemainingCount = 0
    @Published var batchCurrentURL: String = ""
    @Published var celebrationToken = 0
    @Published var liveDownloadedFileCount = 0
    @Published var liveCreatedFolderCount = 0
    @Published var latestSessionDownloadedItems: [WorkerItem] = []
    @Published var postProcessedItems: [PostProcessedItem] = []
    @Published var postProcessingSummary: String = "Постобработка ещё не запускалась."
    @Published var googleDriveLinkSummary: String = "Ссылки Google Drive ещё не собирались."
    @Published var rememberedBloggers: [RememberedBlogger] = []

    let worker = WorkerClient()
    let bootstrapper = WorkerBootstrapper()
    let appUpdater = AppUpdater()
    var hasPrepared = false
    var saveDirectoryBaselineFiles = 0
    var saveDirectoryBaselineFolders = 0
    var liveTrackingTask: Task<Void, Never>?
    var sleepPreventionActivity: NSObjectProtocol?
    var isDownloadActivityInProgress = false
    var pendingEmptyStoryFolders: [URL] = []
    var hasEmbeddedRuntime: Bool { AppPaths.hasEmbeddedRuntime }
    var runtimeOnboardingDismissed: Bool {
        UserDefaults.standard.bool(forKey: Self.runtimeOnboardingDismissedKey)
    }

    init() {
        updateSummary = appUpdater.summary
        canCheckForUpdates = appUpdater.isAvailable
        if let savedDirectory = UserDefaults.standard.string(forKey: Self.saveDirectoryKey),
           !savedDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            saveDirectory = URL(fileURLWithPath: savedDirectory, isDirectory: true)
        }
        if let distributionRoot = UserDefaults.standard.string(forKey: Self.distributionRootDirectoryKey),
           !distributionRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            distributionRootDirectory = URL(fileURLWithPath: distributionRoot, isDirectory: true)
        }
        if let sortingSource = UserDefaults.standard.string(forKey: Self.sortingSourceDirectoryKey),
           !sortingSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            sortingSourceDirectory = URL(fileURLWithPath: sortingSource, isDirectory: true)
        }
        if let savedRules = UserDefaults.standard.string(forKey: Self.folderRoutingRulesKey) {
            folderRoutingRules = savedRules
        }
        loadRememberedBloggers()
        if let savedMediaMode = UserDefaults.standard.string(forKey: Self.mediaSelectionModeKey),
           let mode = MediaSelectionMode(rawValue: savedMediaMode)
        {
            mediaSelectionMode = mode
        }
        if UserDefaults.standard.object(forKey: Self.preventSleepDuringDownloadsKey) != nil {
            preventSleepDuringDownloads = UserDefaults.standard.bool(forKey: Self.preventSleepDuringDownloadsKey)
        }
        loadRecentBatchLists()
    }

    func triggerCelebration() {
        celebrationToken += 1
        playSuccessSound()
    }

    func playActionSound() {
        for name in Self.actionSoundNames {
            if let sound = NSSound(named: NSSound.Name(name)) {
                sound.volume = 0.48
                sound.play()
                return
            }
        }
    }

    private func playSuccessSound() {
        for name in Self.successSoundNames {
            if let sound = NSSound(named: NSSound.Name(name)) {
                sound.volume = 0.72
                sound.play()
                return
            }
        }
    }

    func appendLog(_ message: String) {
        logs.insert("\(Self.logDateFormatter.string(from: Date()))  \(message)", at: 0)
    }

    func dismissRuntimeOnboarding() {
        showRuntimeOnboarding = false
        UserDefaults.standard.set(true, forKey: Self.runtimeOnboardingDismissedKey)
    }
}
