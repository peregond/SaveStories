import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let recentBatchListsKey = "SaveStories.recentBatchLists"
    private static let mediaSelectionModeKey = "SaveStories.mediaSelectionMode"
    static let saveDirectoryKey = "SaveStories.saveDirectory"
    private static let actionSoundNames = ["Pop", "Tink", "Glass"]
    private static let successSoundNames = ["Glass", "Hero", "Funk", "Pop"]
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter
    }()

    struct BatchWorkerResult: Decodable {
        let url: String
        let status: String
        let message: String
        let foundCount: Int
        let savedCount: Int
    }

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

    @Published var profileURL: String = ""
    @Published var batchInput: String = ""
    @Published var batchQueue: [BatchProfileItem] = []
    @Published var downloadMode: DownloadMode = .background
    @Published var mediaSelectionMode: MediaSelectionMode = .videoOnly {
        didSet {
            UserDefaults.standard.set(mediaSelectionMode.rawValue, forKey: Self.mediaSelectionModeKey)
        }
    }
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
    @Published var updateSummary: String = "Автообновление ещё не настроено для этой сборки."
    @Published var canCheckForUpdates = false
    @Published var downloadedItems: [WorkerItem] = []
    @Published var logs: [String] = []
    @Published var isBusy = false
    @Published var workerReady = false
    @Published var sessionReady = false
    @Published var showLoginPrompt = false
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

    let worker = WorkerClient()
    let bootstrapper = WorkerBootstrapper()
    let appUpdater = AppUpdater()
    var hasPrepared = false
    var saveDirectoryBaselineFiles = 0
    var saveDirectoryBaselineFolders = 0
    var liveTrackingTask: Task<Void, Never>?
    var hasEmbeddedRuntime: Bool { AppPaths.hasEmbeddedRuntime }

    init() {
        updateSummary = appUpdater.summary
        canCheckForUpdates = appUpdater.isAvailable
        if let savedDirectory = UserDefaults.standard.string(forKey: Self.saveDirectoryKey),
           !savedDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            saveDirectory = URL(fileURLWithPath: savedDirectory, isDirectory: true)
        }
        if let savedMediaMode = UserDefaults.standard.string(forKey: Self.mediaSelectionModeKey),
           let mode = MediaSelectionMode(rawValue: savedMediaMode)
        {
            mediaSelectionMode = mode
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
}
