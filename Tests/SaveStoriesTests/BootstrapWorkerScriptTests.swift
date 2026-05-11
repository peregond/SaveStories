import Foundation
import XCTest

final class BootstrapWorkerScriptTests: XCTestCase {
    func testBootstrapDoesNotDeleteInstalledNodeRuntimeWhenSyncingWorker() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot
            .appendingPathComponent("Sources/SaveStories/Resources/bootstrap_worker.sh")

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveMeBootstrapTest-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let appSupport = tempRoot.appendingPathComponent("Application Support", isDirectory: true)
        let workerRoot = appSupport.appendingPathComponent("worker", isDirectory: true)
        let nodeBin = workerRoot
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let nodeExecutable = nodeBin.appendingPathComponent("node")
        let npmExecutable = nodeBin.appendingPathComponent("npm")
        let nodeLibrary = workerRoot
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)

        try FileManager.default.createDirectory(at: nodeBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeLibrary, withIntermediateDirectories: true)
        try "runtime payload".write(
            to: nodeLibrary.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        try """
        #!/bin/zsh
        if [ "$1" = "-p" ]; then
          printf '24\n'
          exit 0
        fi
        printf 'fake node\n'
        exit 0
        """.write(to: nodeExecutable, atomically: true, encoding: .utf8)
        try """
        #!/bin/zsh
        mkdir -p node_modules/playwright
        printf 'fake npm\n'
        exit 0
        """.write(to: npmExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nodeExecutable.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: npmExecutable.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = repositoryRoot
        var environment = ProcessInfo.processInfo.environment
        environment["SAVESTORIES_APP_SUPPORT"] = appSupport.path
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nodeLibrary.appendingPathComponent("keep.txt").path))
        XCTAssertFalse(output.contains("cannot delete"), output)
    }
}
