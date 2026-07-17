import Foundation

extension AppModel {
    func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        let message = appUpdater.checkForUpdates()
        appendLog(message)
    }

    func checkForUpdatesOnLaunch() {
        let message = appUpdater.checkForUpdatesOnLaunch()
        appendLog(message)
    }

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        appUpdater.setAutomaticUpdatesEnabled(enabled)
    }

    func installReadyUpdate() {
        appendLog(appUpdater.installReadyUpdate())
    }

    func applyUpdateSnapshot(_ snapshot: AppUpdateSnapshot) {
        updateSummary = snapshot.summary
        canCheckForUpdates = snapshot.isAvailable
        automaticUpdatesEnabled = snapshot.automaticUpdatesEnabled
        isCheckingForUpdates = snapshot.isChecking
        readyUpdateVersion = snapshot.readyVersion
    }
}
