import XCTest
@testable import SaveMe

final class FileDistributionServiceTests: XCTestCase {
    func testScanDistributeAndUndoPreserveExpectedFolders() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("На перенос", isDirectory: true)
        let creator = source.appendingPathComponent("alice", isDirectory: true)
        let destination = root.appendingPathComponent("WhiteList INF", isDirectory: true)
        let originalFile = creator.appendingPathComponent("alice-001.mp4")
        try FileManager.default.createDirectory(at: creator, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32).write(to: originalFile)

        let scan = try FileDistributionService.scanInputs(
            in: source,
            mapping: ["alice": "Germany (DE) INF"]
        )
        XCTAssertEqual(scan.inputs.count, 1)
        XCTAssertEqual(scan.inputs[0].targetRelativeFolder, "Germany (DE) INF/alice")

        let distribution = FileDistributionService.distribute(inputs: scan.inputs, destinationRoot: destination)
        XCTAssertEqual(distribution.movedCount, 1)
        XCTAssertTrue(distribution.failedFileNames.isEmpty)
        let movedFile = try XCTUnwrap(distribution.records.first?.currentURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFile.path))

        let undo = FileDistributionService.undo([
            FileDistributionUndoInput(
                id: scan.inputs[0].id,
                currentURL: movedFile,
                originalURL: originalFile
            ),
        ])
        XCTAssertEqual(undo.restoredRecords.count, 1)
        XCTAssertTrue(undo.failedFileNames.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalFile.path))
    }

    func testUnsafeRoutingPathFallsBackToCreatorFolder() {
        XCTAssertEqual(
            FileDistributionService.targetRelativeFolderPath(
                for: "alice",
                mapping: ["alice": "../../Outside"]
            ),
            "alice"
        )
    }

    func testDistributionDoesNotFollowDestinationSymlinkOutsideRoot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = root.appendingPathComponent("destination", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let sourceFile = root.appendingPathComponent("clip.mp4")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("Country"),
            withDestinationURL: outside
        )
        try Data(repeating: 2, count: 32).write(to: sourceFile)

        let result = FileDistributionService.distribute(
            inputs: [
                FileDistributionInput(
                    id: "clip",
                    originalUsername: "alice",
                    currentURL: sourceFile,
                    targetRelativeFolder: "Country/alice"
                ),
            ],
            destinationRoot: destination
        )

        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(result.failedFileNames, ["clip.mp4"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("alice/clip.mp4").path))
    }

    func testFileAlreadyInDestinationIsNotRenamed() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = root.appendingPathComponent("Country/alice", isDirectory: true)
        let file = folder.appendingPathComponent("alice-001.mp4")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 32).write(to: file)

        let result = FileDistributionService.distribute(
            inputs: [
                FileDistributionInput(
                    id: "same",
                    originalUsername: "alice",
                    currentURL: file,
                    targetRelativeFolder: "Country/alice"
                ),
            ],
            destinationRoot: root
        )

        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(result.records.first?.currentURL.standardizedFileURL, file.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("alice-002.mp4").path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveMeFileDistributionTests-\(UUID().uuidString)", isDirectory: true)
    }
}
