import Foundation

extension AppModel {
    func checkForUpdates() async {
        let message = appUpdater.checkForUpdates()
        updateSummary = appUpdater.summary
        canCheckForUpdates = appUpdater.isAvailable
        appendLog(message)
    }
}
