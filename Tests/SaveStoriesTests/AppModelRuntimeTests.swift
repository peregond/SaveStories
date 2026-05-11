import XCTest
@testable import SaveMe

@MainActor
final class AppModelRuntimeTests: XCTestCase {
    func testSleepPreventionDisablesSystemAndDisplaySleep() {
        XCTAssertTrue(AppModel.sleepPreventionActivityOptions.contains(.idleSystemSleepDisabled))
        XCTAssertTrue(AppModel.sleepPreventionActivityOptions.contains(.idleDisplaySleepDisabled))
    }

    func testAppendForSuccessfulDownloadPrependsItemsUpdatesCountsAndCelebrates() {
        let model = AppModel()
        model.downloadedItems = [
            WorkerItem(
                id: "existing",
                sourceURL: "https://example.com/existing.jpg",
                pageURL: "https://instagram.com/existing",
                localPath: "/tmp/existing.jpg",
                metadataPath: "/tmp/existing.json",
                mediaType: "image",
                createdAt: "2026-04-01T00:00:00Z"
            )
        ]

        let newItem = WorkerItem(
            id: "new",
            sourceURL: "https://example.com/new.mp4",
            pageURL: "https://instagram.com/new",
            localPath: "/tmp/new.mp4",
            metadataPath: "/tmp/new.json",
            mediaType: "video",
            createdAt: "2026-04-01T00:00:01Z"
        )

        let response = WorkerResponse(
            ok: true,
            status: "download_complete",
            message: "Скачивание завершено.",
            data: [:],
            items: [newItem],
            logs: []
        )

        model.append(response)

        XCTAssertEqual(model.downloadedItems.map(\.id), ["new", "existing"])
        XCTAssertEqual(model.foundStoriesCount, 1)
        XCTAssertEqual(model.savedStoriesCount, 1)
        XCTAssertEqual(model.statusTitle, "Готово")
        XCTAssertEqual(model.statusDetail, "Скачивание завершено.")
        XCTAssertEqual(model.lastResult, "Скачивание завершено.")
        XCTAssertEqual(model.currentStepLabel, "Обработка завершена.")
        XCTAssertEqual(model.celebrationToken, 1)
    }

    func testAppendForCancelledResponseMarksOperationStopped() {
        let model = AppModel()

        let response = WorkerResponse.cancelled(message: "Операция отменена пользователем.")

        model.append(response)

        XCTAssertEqual(model.statusTitle, "Остановлено")
        XCTAssertEqual(model.statusDetail, "Операция отменена пользователем.")
        XCTAssertEqual(model.lastResult, "Операция отменена пользователем.")
        XCTAssertEqual(model.currentStepLabel, "Обработка завершилась ошибкой.")
        XCTAssertEqual(model.celebrationToken, 0)
    }

    func testHandleWorkerProgressTracksCurrentBatchProfile() {
        let model = AppModel()
        model.batchQueue = [
            AppModel.BatchProfileItem(url: "done", status: .completed, message: ""),
            AppModel.BatchProfileItem(url: "running", status: .running, message: ""),
            AppModel.BatchProfileItem(url: "pending", status: .pending, message: "")
        ]
        model.batchTotalCount = 3

        model.handleWorkerProgress("batch_profile_start=https://www.instagram.com/running/")

        XCTAssertEqual(model.batchCurrentIndex, 2)
        XCTAssertEqual(model.batchRemainingCount, 1)
        XCTAssertEqual(model.batchCurrentURL, "https://www.instagram.com/running/")
        XCTAssertEqual(model.currentStepLabel, "Открываю профиль running.")
    }

    func testHandleWorkerProgressRecognizesWorkerMilestones() {
        let model = AppModel()

        model.handleWorkerProgress("opened_active_story")
        XCTAssertEqual(model.currentStepLabel, "Открываю stories viewer.")

        model.handleWorkerProgress("storage_state_saved=/tmp/state.json")
        XCTAssertEqual(model.currentStepLabel, "Сохраняю браузерную сессию.")

        model.handleWorkerProgress("playwright=/tmp/ms-playwright")
        XCTAssertEqual(model.currentStepLabel, "Проверяю runtime и зависимости.")
    }

    func testRuntimeSetupProgressMapsInstallerStages() {
        let model = AppModel()

        model.applyRuntimeSetupProgress("Готовлю папку worker: /tmp/worker")
        XCTAssertEqual(model.runtimeSetupStage, .folders)
        XCTAssertEqual(model.runtimeSetupMessage, "Готовлю локальную папку для движка.")

        model.applyRuntimeSetupProgress("Скачиваю Node 24 LTS...")
        XCTAssertEqual(model.runtimeSetupStage, .node)
        XCTAssertEqual(model.runtimeSetupMessage, "Скачиваю Node 24 LTS.")

        model.applyRuntimeSetupProgress("Копирую worker...")
        XCTAssertEqual(model.runtimeSetupStage, .worker)

        model.applyRuntimeSetupProgress("Устанавливаю npm зависимости...")
        XCTAssertEqual(model.runtimeSetupStage, .packages)

        model.applyRuntimeSetupProgress("Скачиваю Chromium...")
        XCTAssertEqual(model.runtimeSetupStage, .browser)
    }

    func testRuntimeSetupFailureSummaryRemovesTransferProgressNoise() {
        let model = AppModel()
        let summary = model.runtimeSetupFailureSummary(from: """
        % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
        Dload  Upload   Total   Spent    Left  Speed
        0 49.0M    0 77793    0     0   194k      0  0:04:18 --:--:--  193k
        rsync(3354): warning: /Users/test/worker/node/lib: not empty, cannot delete
        Не удалось установить зависимости.
        """)

        XCTAssertFalse(summary.contains("% Total"))
        XCTAssertFalse(summary.contains("Dload"))
        XCTAssertFalse(summary.contains("49.0M"))
        XCTAssertTrue(summary.contains("rsync"))
        XCTAssertTrue(summary.contains("Не удалось установить зависимости."))
    }
}
