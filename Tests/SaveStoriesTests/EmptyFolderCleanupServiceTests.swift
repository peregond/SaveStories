import XCTest
@testable import SaveMe

final class EmptyFolderCleanupServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveMeCleanupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    func testFindsOnlyTrulyEmptyFoldersAndSkipsTransferFolder() throws {
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let parent = root.appendingPathComponent("parent", isDirectory: true)
        let child = parent.appendingPathComponent("child", isDirectory: true)
        let withFile = root.appendingPathComponent("with-file", isDirectory: true)
        let withDotFile = root.appendingPathComponent("with-dot-file", isDirectory: true)
        let withServiceFile = root.appendingPathComponent("with-service-file", isDirectory: true)
        let transfer = root.appendingPathComponent("На перенос", isDirectory: true)
        let transferChild = transfer.appendingPathComponent("empty", isDirectory: true)

        for directory in [empty, child, withFile, withDotFile, withServiceFile, transferChild] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "media".write(to: withFile.appendingPathComponent("story.mp4"), atomically: true, encoding: .utf8)
        try "secret".write(to: withDotFile.appendingPathComponent(".secret"), atomically: true, encoding: .utf8)
        try "service".write(to: withServiceFile.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)

        let folders = EmptyFolderCleanupService.findDeletableEmptyFolders(in: root)
        let paths = Set(folders.map { $0.standardizedFileURL.path })

        XCTAssertTrue(paths.contains(empty.standardizedFileURL.path))
        XCTAssertTrue(paths.contains(parent.standardizedFileURL.path))
        XCTAssertTrue(paths.contains(child.standardizedFileURL.path))
        XCTAssertTrue(paths.contains(withServiceFile.standardizedFileURL.path))
        XCTAssertFalse(paths.contains(withFile.standardizedFileURL.path))
        XCTAssertFalse(paths.contains(withDotFile.standardizedFileURL.path))
        XCTAssertFalse(paths.contains(transfer.standardizedFileURL.path))
        XCTAssertFalse(paths.contains(transferChild.standardizedFileURL.path))
    }

    func testDeleteRechecksFoldersBeforeRemoving() throws {
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let withFile = root.appendingPathComponent("with-file", isDirectory: true)
        let transfer = root.appendingPathComponent("На перенос", isDirectory: true)

        for directory in [empty, withFile, transfer] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "media".write(to: withFile.appendingPathComponent("story.mp4"), atomically: true, encoding: .utf8)

        let result = EmptyFolderCleanupService.deleteEmptyFolders([empty, withFile, transfer])

        XCTAssertEqual(result.removedFolderNames, ["empty"])
        XCTAssertTrue(result.failedFolders.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: withFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: transfer.path))
    }
}
