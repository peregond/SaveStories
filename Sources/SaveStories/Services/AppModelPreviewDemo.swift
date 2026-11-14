import Foundation

extension AppModel {
    /// Только для режима предпросмотра дизайна: разыгрывает загрузку очереди на вымышленных профилях,
    /// чтобы проверить анимации прогресса. Сеть, воркер и файловая система не используются.
    @MainActor
    func runPreviewDemoDownload() async {
        guard isDesignPreview, !batchIsRunning else { return }
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

        let names = ["anna.travel", "berlin.food", "mark.fit", "olga.design", "studio.north", "daily.kate"]
        batchQueue = names.map { BatchProfileItem(url: "https://www.instagram.com/\($0)/") }
        foundStoriesCount = 0
        savedStoriesCount = 0
        liveDownloadedFileCount = 0
        liveCreatedFolderCount = 0
        await pause(1.2)

        isBusy = true
        batchIsRunning = true
        batchTotalCount = batchQueue.count
        batchRemainingCount = batchQueue.count
        statusTitle = L("Идёт загрузка")
        statusDetail = L("Приложение работает, дождитесь завершения текущего шага.")

        for index in batchQueue.indices {
            batchCurrentIndex = index + 1
            batchCurrentURL = batchQueue[index].url
            batchQueue[index].status = .running
            batchQueue[index].message = L("Открываю профиль…")
            currentStepLabel = L("Открываю профиль…")
            await pause(0.9)

            let found = 2 + index % 4
            foundStoriesCount += found
            batchQueue[index].message = L("Найдено stories: {0}", found)
            currentStepLabel = L("Сохраняю файлы…")
            for _ in 0 ..< found {
                await pause(0.35)
                savedStoriesCount += 1
                liveDownloadedFileCount += 1
            }
            liveCreatedFolderCount += 1

            let failed = index == 3
            batchQueue[index].status = failed ? .failed : .completed
            batchQueue[index].message = failed ? L("Профиль недоступен.") : L("Сохранено файлов: {0}", found)
            batchRemainingCount = batchQueue.count - index - 1
            await pause(0.5)
        }

        batchCurrentURL = ""
        batchIsRunning = false
        isBusy = false
        statusTitle = L("Готово")
        statusDetail = L("Приложение готово к работе.")
        currentStepLabel = L("Ожидание команды.")
        celebrationToken += 1
    }
}
