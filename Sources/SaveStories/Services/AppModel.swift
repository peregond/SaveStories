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
    static let emptyFolderCleanupDirectoryKey = "SaveStories.emptyFolderCleanupDirectory"
    static let folderRoutingRulesKey = "SaveStories.folderRoutingRules"
    static let rememberedBloggersKey = "SaveStories.rememberedBloggers"
    private static let preventSleepDuringDownloadsKey = "SaveStories.preventSleepDuringDownloads"
    private static let notionInfluencerSourceEnabledKey = "SaveStories.notionInfluencerSourceEnabled"
    private static let notionRoutingRulesSourceEnabledKey = "SaveStories.notionRoutingRulesSourceEnabled"
    static let notionInfluencerLastRefreshAtKey = "SaveStories.notionInfluencerLastRefreshAt"
    static let notionInfluencerCachedProfilesKey = "SaveStories.notionInfluencerCachedProfiles"
    static let notionRoutingRulesLastRefreshAtKey = "SaveStories.notionRoutingRulesLastRefreshAt"
    static let notionRoutingRulesCachedRulesKey = "SaveStories.notionRoutingRulesCachedRules"
    static let runtimeOnboardingDismissedKey = "SaveStories.runtimeOnboardingDismissed"
    static let maxLogEntries = 2_000
    static let maxDownloadedItems = 500
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
            L("{0} профилей", urls.count)
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
                    L("В очереди")
                case .running:
                    L("Скачивается")
                case .completed:
                    L("Готово")
                case .failed:
                    L("Ошибка")
                case .stopped:
                    L("Остановлено")
                }
            }
        }

        let id: UUID
        var url: String
        var status: Status
        var message: String

        init(id: UUID = UUID(), url: String, status: Status = .pending, message: String = L("Ожидает запуска.")) {
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
            removedCount > 0 ? L("Пустые папки удалены") : L("Удалять нечего")
        }

        var message: String {
            guard removedCount > 0 else {
                return L("После проверки пустых папок для удаления не осталось.")
            }

            let preview = folderNames.prefix(5).joined(separator: "\n")
            if folderNames.count > 5 {
                return L("Удалено пустых папок: {0}.\n\n{1}\nи ещё {2}.", removedCount, preview, folderNames.count - 5)
            }
            return L("Удалено пустых папок: {0}.\n\n{1}", removedCount, preview)
        }
    }

    struct PostProcessedItem: Identifiable, Hashable, Sendable {
        let id: String
        let originalUsername: String
        let targetFolderName: String
        let originalPath: String
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
                L("В фоне")
            case .visible:
                L("Видимо")
            }
        }

        var detail: String {
            switch self {
            case .background:
                L("Браузер не показывается во время выгрузки.")
            case .visible:
                L("Открывает окно Chromium во время выгрузки.")
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
                L("Фото и видео")
            case .videoOnly:
                L("Только видео")
            }
        }

        var detail: String {
            switch self {
            case .all:
                L("Сохраняет все найденные stories: и фото, и видео.")
            case .videoOnly:
                L("Сохраняет только видео-stories. Фото будут пропущены.")
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
                L("Подготовка")
            case .folders:
                L("Папки приложения")
            case .node:
                "Node 24 LTS"
            case .worker:
                "Worker"
            case .packages:
                "Playwright"
            case .browser:
                "Chromium"
            case .ready:
                L("Готово")
            case .failed:
                L("Нужно повторить")
            }
        }

        var detail: String {
            switch self {
            case .welcome:
                L("Сейчас приложение докачает компоненты для работы.")
            case .folders:
                L("Готовим локальное хранилище.")
            case .node:
                L("Проверяем или скачиваем Node.")
            case .worker:
                L("Копируем рабочий модуль.")
            case .packages:
                L("Ставим зависимости.")
            case .browser:
                L("Скачиваем браузер для выгрузки.")
            case .ready:
                L("Движок установлен.")
            case .failed:
                L("Установка не завершилась.")
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
            guard !isDesignPreview else { return }
            UserDefaults.standard.set(mediaSelectionMode.rawValue, forKey: Self.mediaSelectionModeKey)
        }
    }
    @Published var preventSleepDuringDownloads = true {
        didSet {
            guard !isDesignPreview else { return }
            UserDefaults.standard.set(preventSleepDuringDownloads, forKey: Self.preventSleepDuringDownloadsKey)
            refreshSleepPreventionForCurrentState()
        }
    }
    @Published var notionInfluencerSourceEnabled = true {
        didSet {
            guard !isDesignPreview else { return }
            UserDefaults.standard.set(notionInfluencerSourceEnabled, forKey: Self.notionInfluencerSourceEnabledKey)
            if notionInfluencerSourceEnabled {
                notionInfluencerSourceSummary = L("Перед запуском очередь обновится из Notion не чаще одного раза в день.")
            } else {
                notionInfluencerSourceSummary = L("Автосписок Notion выключен.")
            }
        }
    }
    @Published var notionInfluencerSourceSummary = L("Перед запуском очередь обновится из Notion не чаще одного раза в день.")
    @Published var isRefreshingNotionInfluencers = false
    @Published var notionRoutingRulesSourceEnabled = false {
        didSet {
            guard !isDesignPreview else { return }
            UserDefaults.standard.set(notionRoutingRulesSourceEnabled, forKey: Self.notionRoutingRulesSourceEnabledKey)
            notionRoutingRulesSourceSummary = notionRoutingRulesSourceEnabled
                ? L("Перед сортировкой правила обновятся из Notion не чаще одного раза в день.")
                : L("Автоправила Notion выключены.")
        }
    }
    @Published var notionRoutingRulesSourceSummary = L("Автоправила Notion выключены.")
    @Published var isRefreshingNotionRoutingRules = false
    @Published var saveDirectory: URL = AppPaths.defaultDownloads
    @Published var distributionRootDirectory: URL?
    @Published var sortingSourceDirectory: URL?
    @Published var emptyFolderCleanupDirectory: URL?
    @Published var folderRoutingRules: String = "" {
        didSet {
            guard !isDesignPreview else { return }
            UserDefaults.standard.set(folderRoutingRules, forKey: Self.folderRoutingRulesKey)
        }
    }
    @Published var workerSummary: String = L("Воркер ещё не проверялся.")
    @Published var sessionSummary: String = L("Состояние сессии неизвестно.")
    @Published var lastResult: String = L("Действий пока не было.")
    @Published var statusTitle: String = L("Ожидание")
    @Published var statusDetail: String = L("Приложение готово к работе.")
    @Published var currentStepLabel: String = L("Ожидание команды.")
    @Published var foundStoriesCount: Int = 0
    @Published var savedStoriesCount: Int = 0
    @Published var runtimeSummary: String = ""
    @Published var updateSummary: String = L("Автообновление ещё не настроено для этой сборки.")
    @Published var canCheckForUpdates = false
    @Published var automaticUpdatesEnabled = true
    @Published var isCheckingForUpdates = false
    @Published var readyUpdateVersion: String?
    @Published var downloadedItems: [WorkerItem] = []
    @Published var logs: [String] = []
    @Published var isBusy = false
    @Published var workerReady = false
    @Published var sessionReady = false
    @Published var showLoginPrompt = false
    @Published var showRuntimeOnboarding = false
    @Published var runtimeSetupStage: RuntimeSetupStage = .welcome
    @Published var runtimeSetupFailedStage: RuntimeSetupStage?
    @Published var runtimeSetupMessage = L("Подготовим движок, без которого приложение не сможет скачивать stories.")
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
    @Published var postProcessingSummary: String = L("Постобработка ещё не запускалась.")
    @Published var emptyFolderCleanupSummary: String = L("Очистка пустых папок ещё не запускалась.")
    @Published var googleDriveLinkSummary: String = L("Ссылки Google Drive ещё не собирались.")
    @Published var rememberedBloggers: [RememberedBlogger] = []

    let worker = WorkerClient()
    /// Раздел «Уникализатор»: своё состояние и свой процесс воркера; изменения пробрасываются в интерфейс через AppModel.
    let unikalizator: UnikalizatorModel
    private var unikalizatorChanges: AnyCancellable?
    let bootstrapper = WorkerBootstrapper()
    let appUpdater: AppUpdater
    let isDesignPreview: Bool
    var hasPrepared = false
    var saveDirectoryBaselineFiles = 0
    var saveDirectoryBaselineFolders = 0
    var liveTrackingTask: Task<Void, Never>?
    var sleepPreventionActivity: NSObjectProtocol?
    var isDownloadActivityInProgress = false
    var pendingEmptyStoryFolders: [URL] = []
    var batchProgressStartedURLs = Set<String>()
    var batchProgressCompletedURLs = Set<String>()
    var hasEmbeddedRuntime: Bool { AppPaths.hasEmbeddedRuntime }
    var runtimeOnboardingDismissed: Bool {
        guard !isDesignPreview else { return true }
        return UserDefaults.standard.bool(forKey: Self.runtimeOnboardingDismissedKey)
    }

    init(isDesignPreview: Bool = false) {
        self.isDesignPreview = isDesignPreview
        unikalizator = UnikalizatorModel(isPreview: isDesignPreview)
        appUpdater = AppUpdater(isEnabled: !isDesignPreview)
        // Все свойства уже заданы — можно подписаться: изменения раздела «Уникализатор» перерисовывают интерфейс.
        unikalizatorChanges = unikalizator.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        if isDesignPreview {
            saveDirectory = URL(fileURLWithPath: "/Users/preview/Downloads/SaveMe", isDirectory: true)
            workerReady = true
            sessionReady = true
            workerSummary = L("Движок готов к работе.")
            sessionSummary = L("Демонстрационная сессия.")
            statusDetail = L("Добавьте профили, чтобы начать загрузку.")
            updateSummary = L("Предпросмотр дизайна — обновления отключены.")
            notionInfluencerSourceEnabled = false
            return
        }
        UserDefaults.standard.register(defaults: [
            Self.notionInfluencerSourceEnabledKey: true,
        ])
        updateSummary = appUpdater.summary
        canCheckForUpdates = appUpdater.isAvailable
        automaticUpdatesEnabled = appUpdater.automaticUpdatesEnabled
        appUpdater.stateDidChange = { [weak self] snapshot in
            self?.applyUpdateSnapshot(snapshot)
        }
        saveDirectory = Self.persistedDirectoryURL(forKey: Self.saveDirectoryKey) ?? AppPaths.defaultDownloads
        distributionRootDirectory = Self.persistedDirectoryURL(forKey: Self.distributionRootDirectoryKey)
        sortingSourceDirectory = Self.persistedDirectoryURL(forKey: Self.sortingSourceDirectoryKey)
        emptyFolderCleanupDirectory = Self.persistedDirectoryURL(forKey: Self.emptyFolderCleanupDirectoryKey)
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
        notionInfluencerSourceEnabled = UserDefaults.standard.bool(forKey: Self.notionInfluencerSourceEnabledKey)
        notionInfluencerSourceSummary = notionInfluencerSourceEnabled
            ? L("Перед запуском очередь обновится из Notion не чаще одного раза в день.")
            : L("Автосписок Notion выключен.")
        notionRoutingRulesSourceEnabled = UserDefaults.standard.bool(forKey: Self.notionRoutingRulesSourceEnabledKey)
        notionRoutingRulesSourceSummary = notionRoutingRulesSourceEnabled
            ? L("Перед сортировкой правила обновятся из Notion не чаще одного раза в день.")
            : L("Автоправила Notion выключены.")
        loadRecentBatchLists()
    }

    func wasNotionSourceRefreshedToday(key: String) -> Bool {
        guard !isDesignPreview else { return false }
        guard let date = UserDefaults.standard.object(forKey: key) as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(date)
    }

    func markNotionSourceRefreshed(key: String) {
        guard !isDesignPreview else { return }
        UserDefaults.standard.set(Date(), forKey: key)
    }

    func triggerCelebration() {
        celebrationToken += 1
        playSuccessSound()
    }

    func playActionSound() {
        guard !isDesignPreview else { return }
        for name in Self.actionSoundNames {
            if let sound = NSSound(named: NSSound.Name(name)) {
                sound.volume = 0.48
                sound.play()
                return
            }
        }
    }

    private func playSuccessSound() {
        guard !isDesignPreview else { return }
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
        if logs.count > Self.maxLogEntries {
            logs.removeLast(logs.count - Self.maxLogEntries)
        }
    }

    private static func persistedDirectoryURL(forKey key: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key),
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    nonisolated static func existingDirectory(_ url: URL?) -> URL? {
        guard let url else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return url
    }

    func dismissRuntimeOnboarding() {
        showRuntimeOnboarding = false
        guard !isDesignPreview else { return }
        UserDefaults.standard.set(true, forKey: Self.runtimeOnboardingDismissedKey)
    }
}
