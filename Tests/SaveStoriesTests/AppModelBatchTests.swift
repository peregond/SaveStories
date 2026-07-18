import XCTest
@testable import SaveMe

@MainActor
final class AppModelBatchTests: XCTestCase {
    private let recentBatchListsKey = "SaveStories.recentBatchLists"
    private let notionInfluencerSourceEnabledKey = "SaveStories.notionInfluencerSourceEnabled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: recentBatchListsKey)
        UserDefaults.standard.removeObject(forKey: notionInfluencerSourceEnabledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: recentBatchListsKey)
        UserDefaults.standard.removeObject(forKey: notionInfluencerSourceEnabledKey)
        super.tearDown()
    }

    func testNotionInfluencerQueueRefreshDefaultsToEnabled() {
        let model = AppModel()

        XCTAssertTrue(model.notionInfluencerSourceEnabled)
    }

    func testNotionInfluencerQueueRefreshPreservesExplicitDisabledPreference() {
        UserDefaults.standard.set(false, forKey: notionInfluencerSourceEnabledKey)

        let model = AppModel()

        XCTAssertFalse(model.notionInfluencerSourceEnabled)
    }

    func testParsedBatchLinksSplitsNewlinesCommasAndWhitespace() {
        let model = AppModel()

        let parsed = model.parsedBatchLinks(from: " alice \nhttps://www.instagram.com/bob/ , @carol,,\n\n dima @upngo____;@stoffer__ ")

        XCTAssertEqual(
            parsed,
            ["alice", "https://www.instagram.com/bob/", "@carol", "dima", "@upngo____", "@stoffer__"]
        )
    }

    func testNormalizedProfileLinkNormalizesUsernamesAndKeepsInstagramURLs() {
        let model = AppModel()

        XCTAssertEqual(
            model.normalizedProfileLink(" @alice/ "),
            "https://www.instagram.com/alice/"
        )
        XCTAssertEqual(
            model.normalizedProfileLink("@upngo____"),
            "https://www.instagram.com/upngo____/"
        )
        XCTAssertEqual(
            model.normalizedProfileLink("@*berthi*"),
            "https://www.instagram.com/berthi/"
        )
        XCTAssertEqual(
            model.normalizedProfileLink("https://www.instagram.com/bob/"),
            "https://www.instagram.com/bob/"
        )
        XCTAssertEqual(
            model.normalizedProfileLink("HTTPS://WWW.INSTAGRAM.COM/Bob/?hl=en"),
            "https://www.instagram.com/Bob/"
        )
        XCTAssertEqual(model.normalizedProfileLink("https://www.instagram.com/reel/abc/"), "")
        XCTAssertEqual(model.normalizedProfileLink("https://evilinstagram.com/alice/"), "")
        XCTAssertEqual(model.normalizedProfileLink("https://example.com/alice/"), "")
        XCTAssertEqual(model.normalizedProfileLink("ftp://instagram.com/alice/"), "")
        XCTAssertEqual(model.normalizedProfileLink("alice/bob"), "")
        XCTAssertEqual(model.normalizedProfileLink("@***"), "")
    }

    func testNormalizedBatchLinksDropsInvalidAndCaseInsensitiveDuplicates() {
        let model = AppModel()

        XCTAssertEqual(
            model.normalizedBatchLinks(
                from: "@Alice\nhttps://www.instagram.com/alice/?hl=en\nhttps://www.instagram.com/reel/abc/\n@bob"
            ),
            [
                "https://www.instagram.com/Alice/",
                "https://www.instagram.com/bob/",
            ]
        )
    }

    func testApplyBatchResultsMapsWorkerStatusesAndMissingProfiles() {
        let model = AppModel()
        let alice = AppModel.BatchProfileItem(url: "alice")
        let bob = AppModel.BatchProfileItem(url: "bob")
        let carol = AppModel.BatchProfileItem(url: "carol")
        model.batchQueue = [alice, bob, carol]

        let batchResults = """
        [
          {"url":"alice","status":"completed","message":"Alice done","foundCount":3,"savedCount":2},
          {"url":"https://www.instagram.com/bob/","status":"stopped","message":"Bob stopped","foundCount":1,"savedCount":0}
        ]
        """

        let response = WorkerResponse(
            ok: true,
            status: "download_complete",
            message: "Batch finished",
            data: [
                "foundCount": "4",
                "savedCount": "2",
                "batchResults": batchResults,
            ],
            items: [],
            logs: []
        )

        model.applyBatchResults(response, pendingItems: [alice, bob, carol])

        XCTAssertEqual(model.foundStoriesCount, 4)
        XCTAssertEqual(model.savedStoriesCount, 2)
        XCTAssertEqual(model.batchQueue[0].status, .completed)
        XCTAssertEqual(model.batchQueue[0].message, "Alice done")
        XCTAssertEqual(model.batchQueue[1].status, .stopped)
        XCTAssertEqual(model.batchQueue[1].message, "Bob stopped")
        XCTAssertEqual(model.batchQueue[2].status, .failed)
        XCTAssertEqual(model.batchQueue[2].message, "Для профиля нет результата пакетной выгрузки.")
    }

    func testApplyBatchResultsToleratesDuplicateWorkerEntries() {
        let model = AppModel()
        let alice = AppModel.BatchProfileItem(url: "alice")
        model.batchQueue = [alice]
        let duplicate = WorkerBatchResult(
            url: "alice",
            status: "completed",
            message: "Done",
            foundCount: 1,
            savedCount: 1
        )
        let response = WorkerResponse(
            ok: true,
            status: "batch_complete",
            message: "Done",
            data: [:],
            batchResults: [duplicate, duplicate],
            items: [],
            logs: []
        )

        model.applyBatchResults(response, pendingItems: [alice])

        XCTAssertEqual(model.batchQueue[0].status, .completed)
    }

    func testStoreRecentBatchListDeduplicatesPersistsAndCapsHistory() {
        let model = AppModel()

        model.storeRecentBatchList(title: "First", urls: ["alice", "bob"])
        model.storeRecentBatchList(title: "Updated", urls: ["@alice", "https://www.instagram.com/bob/"])

        XCTAssertEqual(model.recentBatchLists.count, 1)
        XCTAssertEqual(model.recentBatchLists[0].title, "Updated")
        XCTAssertEqual(
            model.recentBatchLists[0].urls,
            ["https://www.instagram.com/alice/", "https://www.instagram.com/bob/"]
        )

        for index in 1...9 {
            model.storeRecentBatchList(title: "List \(index)", urls: ["user\(index)"])
        }

        XCTAssertEqual(model.recentBatchLists.count, 8)
        XCTAssertEqual(model.recentBatchLists.first?.title, "List 9")
        XCTAssertFalse(model.recentBatchLists.contains(where: { $0.title == "Updated" }))

        let reloaded = AppModel()
        XCTAssertEqual(reloaded.recentBatchLists.count, 8)
        XCTAssertEqual(reloaded.recentBatchLists.first?.title, "List 9")
    }

    func testLoadRecentBatchListsRepairsInvalidAndDuplicateURLs() throws {
        let stored = [
            AppModel.RecentBatchList(
                title: "Legacy",
                urls: [
                    "@Alice",
                    "https://www.instagram.com/alice/?hl=en",
                    "https://www.instagram.com/reel/invalid/",
                ]
            ),
            AppModel.RecentBatchList(title: "Invalid", urls: ["https://evilinstagram.com/alice/"]),
        ]
        UserDefaults.standard.set(try JSONEncoder().encode(stored), forKey: recentBatchListsKey)

        let model = AppModel()

        XCTAssertEqual(model.recentBatchLists.count, 1)
        XCTAssertEqual(model.recentBatchLists[0].title, "Legacy")
        XCTAssertEqual(model.recentBatchLists[0].urls, ["https://www.instagram.com/Alice/"])
    }
}
