import Foundation

extension AppModel {
    func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        let message = appUpdater.checkForUpdates()
        updateSummary = appUpdater.summary
        canCheckForUpdates = appUpdater.isAvailable
        appendLog(message)
    }
}
