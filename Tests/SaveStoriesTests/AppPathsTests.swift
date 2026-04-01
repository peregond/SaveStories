import XCTest
@testable import SaveStories

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
}
