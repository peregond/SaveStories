import Foundation
import XCTest
@testable import SaveMe

final class AppPathsTests: XCTestCase {
    func testApplicationSupportUsesEnvironmentOverride() {
        let overridePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("savestories-tests-\(UUID().uuidString)", isDirectory: true)

        setenv("SAVESTORIES_APP_SUPPORT", overridePath.path, 1)
        defer {
            unsetenv("SAVESTORIES_APP_SUPPORT")
        }

        XCTAssertEqual(AppPaths.applicationSupport.path, overridePath.path)
        XCTAssertEqual(
            AppPaths.workerRoot.path,
            overridePath.appendingPathComponent("worker", isDirectory: true).path
        )
        XCTAssertEqual(
            AppPaths.manifestsDirectory.path,
            overridePath.appendingPathComponent("manifests", isDirectory: true).path
        )
    }

    func testWorkerSourceSynchronizationRefreshesCodeAndPreservesRuntimeAndSessionState() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SaveMe-worker-sync-\(UUID().uuidString)", isDirectory: true)
        let bundledWorker = testRoot.appendingPathComponent("bundled", isDirectory: true)
        let installedWorker = testRoot.appendingPathComponent("installed", isDirectory: true)
        defer { try? fileManager.removeItem(at: testRoot) }

        try write("{\"version\":\"0.6.74\"}", to: bundledWorker.appendingPathComponent("package.json"))
        try write("new bridge", to: bundledWorker.appendingPathComponent("bridge.mjs"))
        try write("new helper", to: bundledWorker.appendingPathComponent("lib/helper.mjs"))
        try write("bundled runtime", to: bundledWorker.appendingPathComponent("node/bin/node"))
        try write("bundled dependency", to: bundledWorker.appendingPathComponent("node_modules/playwright/index.js"))
        try write("bundled browser", to: bundledWorker.appendingPathComponent("ms-playwright/chromium/version"))
        try write("bundled profile", to: bundledWorker.appendingPathComponent("browser-profile/Default/Cookies"))
        try write("bundled session", to: bundledWorker.appendingPathComponent("storage-state.json"))

        try write("{\"version\":\"0.6.33\"}", to: installedWorker.appendingPathComponent("package.json"))
        try write("old bridge", to: installedWorker.appendingPathComponent("bridge.mjs"))
        try write("obsolete source", to: installedWorker.appendingPathComponent("obsolete.mjs"))
        try write("installed runtime", to: installedWorker.appendingPathComponent("node/bin/node"))
        try write("installed dependency", to: installedWorker.appendingPathComponent("node_modules/playwright/index.js"))
        try write("installed browser", to: installedWorker.appendingPathComponent("ms-playwright/chromium/version"))
        try write("installed profile", to: installedWorker.appendingPathComponent("browser-profile/Default/Cookies"))
        try write("installed session", to: installedWorker.appendingPathComponent("storage-state.json"))
        try write("installed legacy runtime", to: installedWorker.appendingPathComponent(".venv/bin/python3"))

        XCTAssertTrue(
            try AppPaths.synchronizeNodeWorkerSources(
                from: bundledWorker,
                to: installedWorker,
                using: fileManager
            )
        )

        XCTAssertEqual(try read(installedWorker.appendingPathComponent("package.json")), "{\"version\":\"0.6.74\"}")
        XCTAssertEqual(try read(installedWorker.appendingPathComponent("bridge.mjs")), "new bridge")
        XCTAssertEqual(try read(installedWorker.appendingPathComponent("lib/helper.mjs")), "new helper")
        XCTAssertFalse(fileManager.fileExists(atPath: installedWorker.appendingPathComponent("obsolete.mjs").path))

        XCTAssertEqual(try read(installedWorker.appendingPathComponent("node/bin/node")), "installed runtime")
        XCTAssertEqual(
            try read(installedWorker.appendingPathComponent("node_modules/playwright/index.js")),
            "installed dependency"
        )
        XCTAssertEqual(
            try read(installedWorker.appendingPathComponent("ms-playwright/chromium/version")),
            "installed browser"
        )
        XCTAssertEqual(
            try read(installedWorker.appendingPathComponent("browser-profile/Default/Cookies")),
            "installed profile"
        )
        XCTAssertEqual(try read(installedWorker.appendingPathComponent("storage-state.json")), "installed session")
        XCTAssertEqual(try read(installedWorker.appendingPathComponent(".venv/bin/python3")), "installed legacy runtime")

        XCTAssertFalse(
            try AppPaths.synchronizeNodeWorkerSources(
                from: bundledWorker,
                to: installedWorker,
                using: fileManager
            )
        )
    }

    func testInstalledNodeWorkerRootRequiresPlaywrightDependency() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SaveMe-installed-worker-\(UUID().uuidString)", isDirectory: true)
        let workerRoot = testRoot.appendingPathComponent("worker", isDirectory: true)
        defer {
            unsetenv("SAVESTORIES_APP_SUPPORT")
            try? fileManager.removeItem(at: testRoot)
        }
        setenv("SAVESTORIES_APP_SUPPORT", testRoot.path, 1)

        try write("worker", to: workerRoot.appendingPathComponent("bridge.mjs"))
        XCTAssertNil(AppPaths.installedNodeWorkerRoot)

        try write("dependency", to: workerRoot.appendingPathComponent("node_modules/playwright/package.json"))
        XCTAssertEqual(AppPaths.installedNodeWorkerRoot?.path, workerRoot.path)
    }

    func testWorkerSourceSynchronizationRejectsIncompleteBundle() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SaveMe-worker-sync-\(UUID().uuidString)", isDirectory: true)
        let bundledWorker = testRoot.appendingPathComponent("bundled", isDirectory: true)
        let installedWorker = testRoot.appendingPathComponent("installed", isDirectory: true)
        defer { try? fileManager.removeItem(at: testRoot) }

        try write("{\"version\":\"0.6.74\"}", to: bundledWorker.appendingPathComponent("package.json"))
        try write("installed bridge", to: installedWorker.appendingPathComponent("bridge.mjs"))

        XCTAssertThrowsError(
            try AppPaths.synchronizeNodeWorkerSources(
                from: bundledWorker,
                to: installedWorker,
                using: fileManager
            )
        )
        XCTAssertEqual(try read(installedWorker.appendingPathComponent("bridge.mjs")), "installed bridge")
    }

    func testWorkerSourceSynchronizationDoesNotDowngradeNewerInstalledWorker() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SaveMe-worker-version-\(UUID().uuidString)", isDirectory: true)
        let bundledWorker = testRoot.appendingPathComponent("bundled", isDirectory: true)
        let installedWorker = testRoot.appendingPathComponent("installed", isDirectory: true)
        defer { try? fileManager.removeItem(at: testRoot) }

        try write("{\"version\":\"0.6.73\"}", to: bundledWorker.appendingPathComponent("package.json"))
        try write("old bundled bridge", to: bundledWorker.appendingPathComponent("bridge.mjs"))
        try write("{\"version\":\"0.6.74\"}", to: installedWorker.appendingPathComponent("package.json"))
        try write("new installed bridge", to: installedWorker.appendingPathComponent("bridge.mjs"))

        XCTAssertFalse(
            try AppPaths.synchronizeNodeWorkerSources(
                from: bundledWorker,
                to: installedWorker,
                using: fileManager
            )
        )
        XCTAssertEqual(try read(installedWorker.appendingPathComponent("bridge.mjs")), "new installed bridge")
        XCTAssertEqual(try read(installedWorker.appendingPathComponent("package.json")), "{\"version\":\"0.6.74\"}")
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }
}
