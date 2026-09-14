import XCTest
@testable import SaveMe

@MainActor
final class AppModelDesignPreviewTests: XCTestCase {
    func testPreviewUsesSyntheticStateAndDoesNotPrepareRuntime() async {
        let model = AppModel(isDesignPreview: true)

        await model.prepare()
        var didPerformOperation = false
        await model.perform("Preview operation") {
            didPerformOperation = true
        }

        XCTAssertEqual(model.saveDirectory.path, "/Users/preview/Downloads/SaveMe")
        XCTAssertTrue(model.recentBatchLists.isEmpty)
        XCTAssertTrue(model.rememberedBloggers.isEmpty)
        XCTAssertTrue(model.workerReady)
        XCTAssertTrue(model.sessionReady)
        XCTAssertFalse(model.canCheckForUpdates)
        XCTAssertFalse(model.hasPrepared)
        XCTAssertFalse(didPerformOperation)
        let didRefreshInfluencers = await model.refreshNotionInfluencerQueue(force: true)
        let didRefreshRoutingRules = await model.refreshNotionRoutingRules(force: true)
        XCTAssertFalse(didRefreshInfluencers)
        XCTAssertFalse(didRefreshRoutingRules)
    }

    func testManualDownloadRetainsTypedProfilesWhenNotionIsEnabled() async {
        let model = AppModel(isDesignPreview: true)
        model.notionInfluencerSourceEnabled = true
        model.batchQueue = [.init(url: "https://www.instagram.com/existing/")]
        model.batchInput = "@alice\n@bob\n@alice"

        await model.downloadStoriesFromInput()

        XCTAssertEqual(model.batchQueue.map(\.url), [
            "https://www.instagram.com/existing/",
            "https://www.instagram.com/alice/",
            "https://www.instagram.com/bob/",
        ])
        XCTAssertTrue(model.batchInput.isEmpty)
        XCTAssertFalse(model.isRefreshingNotionInfluencers)
        XCTAssertFalse(model.isBusy)
    }

    func testStartingWhileBusyDoesNotConsumeTypedProfiles() async {
        let model = AppModel(isDesignPreview: true)
        model.batchInput = "@alice"
        model.isBusy = true

        await model.downloadStoriesFromInput()

        XCTAssertEqual(model.batchInput, "@alice")
        XCTAssertTrue(model.batchQueue.isEmpty)
    }

    func testPreviewEditsDoNotPersistUserPreferences() {
        let keys = [
            AppModel.folderRoutingRulesKey,
            AppModel.recentBatchListsKey,
            AppModel.runtimeOnboardingDismissedKey,
            "SaveStories.mediaSelectionMode",
            "SaveStories.preventSleepDuringDownloads",
            "SaveStories.notionInfluencerSourceEnabled",
            "SaveStories.notionRoutingRulesSourceEnabled",
        ]
        let before = keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }
        let model = AppModel(isDesignPreview: true)
        model.folderRoutingRules = "preview=demo"
        model.mediaSelectionMode = .all
        model.preventSleepDuringDownloads = false
        model.notionInfluencerSourceEnabled = true
        model.notionRoutingRulesSourceEnabled = true
        model.storeRecentBatchList(title: "Preview", urls: ["example"])
        model.persistFolderRoutingRules()
        model.dismissRuntimeOnboarding()

        let after = keys.map { UserDefaults.standard.object(forKey: $0) as? NSObject }
        XCTAssertEqual(before, after)
    }
}
