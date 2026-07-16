import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppUpdater: NSObject {
    private(set) var isAvailable = false
    private(set) var summary = "Автообновление ещё не настроено для этой сборки."

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
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
        return "Запрашиваю проверку новых версий."
    }

    func start() {
        guard isAvailable, !hasStarted else { return }
        #if canImport(Sparkle)
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        controller.startUpdater()
        #endif
        hasStarted = true
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
}
