import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

struct AppUpdateSnapshot {
    let summary: String
    let isAvailable: Bool
    let automaticUpdatesEnabled: Bool
    let isChecking: Bool
    let readyVersion: String?
}

@MainActor
final class AppUpdater: NSObject {
    private(set) var isAvailable = false
    private(set) var summary = "Автообновление ещё не настроено для этой сборки."
    private(set) var automaticUpdatesEnabled = true
    private(set) var isChecking = false
    private(set) var readyVersion: String?
    var stateDidChange: ((AppUpdateSnapshot) -> Void)?

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    private var immediateInstallHandler: (() -> Void)?
    #endif
    private var hasStarted = false

    override init() {
        super.init()
        configure()
    }

    func checkForUpdates() -> String {
        guard isAvailable else {
            return summary
        }

        start()
        #if canImport(Sparkle)
        updaterController?.checkForUpdates(nil)
        #endif
        isChecking = true
        summary = "Проверяю наличие новой версии."
        publishState()
        return summary
    }

    func checkForUpdatesOnLaunch() -> String {
        guard isAvailable else {
            return summary
        }

        start()
        guard automaticUpdatesEnabled else {
            summary = "Автоматическая проверка обновлений выключена."
            publishState()
            return summary
        }

        #if canImport(Sparkle)
        updaterController?.updater.checkForUpdatesInBackground()
        #endif
        isChecking = true
        summary = "Проверяю обновления в фоне."
        publishState()
        return summary
    }

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        start()

        #if canImport(Sparkle)
        updaterController?.updater.automaticallyChecksForUpdates = enabled
        updaterController?.updater.automaticallyDownloadsUpdates = enabled
        #endif
        automaticUpdatesEnabled = enabled
        summary = enabled
            ? "Обновления будут проверяться и скачиваться при запуске."
            : "Автоматическая проверка обновлений выключена."
        publishState()

        if enabled {
            _ = checkForUpdatesOnLaunch()
        }
    }

    func installReadyUpdate() -> String {
        #if canImport(Sparkle)
        guard let immediateInstallHandler else {
            return "Подготовленное обновление пока недоступно."
        }

        summary = "Устанавливаю обновление и перезапускаю SaveMe."
        publishState()
        immediateInstallHandler()
        return summary
        #else
        return "Sparkle не подключён в текущей сборке."
        #endif
    }

    func start() {
        guard isAvailable, !hasStarted else { return }
        #if canImport(Sparkle)
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        controller.startUpdater()
        automaticUpdatesEnabled = controller.updater.automaticallyChecksForUpdates
            && controller.updater.automaticallyDownloadsUpdates
        #endif
        hasStarted = true
        publishState()
    }

    private func configure() {
        guard let configuration = UpdateConfiguration.load(),
              configuration.macOSFeed != nil
        else {
            summary = "Не удалось загрузить update-config для приложения."
            return
        }

        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String

        guard let publicKey, !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let feedURL, !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            summary = "Release-сборка пока не содержит Sparkle feed или публичный ключ обновлений."
            return
        }

        #if canImport(Sparkle)
        isAvailable = true
        summary = "Автообновление подключено. Источник: \(feedURL)"
        #else
        summary = "Sparkle не подключён в текущей сборке."
        #endif
    }

    private var snapshot: AppUpdateSnapshot {
        AppUpdateSnapshot(
            summary: summary,
            isAvailable: isAvailable,
            automaticUpdatesEnabled: automaticUpdatesEnabled,
            isChecking: isChecking,
            readyVersion: readyVersion
        )
    }

    private func publishState() {
        stateDidChange?(snapshot)
    }
}

#if canImport(Sparkle)
extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        isChecking = true
        summary = "Найдена версия \(item.displayVersionString). Скачиваю обновление."
        publishState()
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        summary = "Версия \(item.displayVersionString) скачана. Проверяю и подготавливаю установку."
        publishState()
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        self.immediateInstallHandler = immediateInstallHandler
        readyVersion = item.displayVersionString
        isChecking = false
        summary = "Версия \(item.displayVersionString) готова к установке."
        publishState()
        return true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        isChecking = false
        summary = "Установлена актуальная версия SaveMe."
        publishState()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        isChecking = false
        summary = "Не удалось проверить обновления: \(error.localizedDescription)"
        publishState()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard readyVersion == nil else { return }
        isChecking = false
        if error == nil,
           summary == "Проверяю наличие новой версии." || summary == "Проверяю обновления в фоне."
        {
            summary = "Проверка обновлений завершена."
        }
        publishState()
    }
}
#endif
