import XCTest
@testable import SaveMe

@MainActor
final class WorkerClientTests: XCTestCase {
    private let responseJSON = #"{"ok":true,"status":"fixture_complete","message":"Fixture completed","data":{},"items":[],"logs":[]}"#

    private func request(_ command: String = "fixture") -> WorkerRequest {
        WorkerRequest(command: command, url: nil, urls: nil, outputDirectory: nil, headless: nil, mediaFilter: nil)
    }

    private func client(script: String) -> WorkerClient {
        WorkerClient(
            prepareEnvironment: {},
            launchConfiguration: .init(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", script],
                runtime: "fixture"
            )
        )
    }

    func testSequentialRequestsReleaseProcessSlotBeforeReturning() async {
        let worker = client(script: "read -r request\nprintf '%s\\n' '\(responseJSON)'")

        for _ in 0..<12 {
            let response = await worker.run(request())
            XCTAssertTrue(response.ok, response.message)
            XCTAssertEqual(response.status, "fixture_complete")
        }
    }

    func testCancellationStopsRunningProcessAndAllowsNextRequest() async throws {
        let worker = client(script: """
        read -r request
        case "$request" in
          *wait*) exec /bin/sleep 5 ;;
          *) printf '%s\\n' '\(responseJSON)' ;;
        esac
        """)
        let running = Task { await worker.run(request("wait")) }
        try await Task.sleep(for: .milliseconds(150))

        let busy = await worker.run(request())
        XCTAssertEqual(busy.status, "process_error")
        let cancellationStartedAt = Date()
        running.cancel()
        let cancelled = await running.value

        XCTAssertEqual(cancelled.status, "cancelled")
        XCTAssertLessThan(Date().timeIntervalSince(cancellationStartedAt), 2)
        let next = await worker.run(request())
        XCTAssertTrue(next.ok, next.message)
    }

    func testAlreadyCancelledTaskDoesNotPrepareOrLaunchWorker() async {
        var preparationCount = 0
        let worker = WorkerClient(prepareEnvironment: { preparationCount += 1 })
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await worker.run(request())
        }

        let response = await operation.value

        XCTAssertEqual(response.status, "cancelled")
        XCTAssertEqual(preparationCount, 0)
    }

    func testInvalidResponseDoesNotExposeRawWorkerOutput() async {
        let rawOutput = "sessionid=private-test-fixture"
        let worker = client(script: "read -r request\nprintf '%s' '\(rawOutput)'")

        let response = await worker.run(request())

        XCTAssertEqual(response.status, "process_error")
        XCTAssertFalse(response.message.contains("private-test-fixture"))
        XCTAssertFalse(response.message.contains("sessionid"))
        XCTAssertTrue(response.message.contains("\(rawOutput.utf8.count) байт"))
    }

    func testLargeStderrDoesNotBlockWorkerResponse() async {
        let worker = client(script: """
        read -r request
        /usr/bin/yes 'fixture progress' | /usr/bin/head -n 12000 >&2
        printf '%s\\n' '\(responseJSON)'
        """)

        let response = await worker.run(request())

        XCTAssertTrue(response.ok, response.message)
    }

    func testLaunchFailureReleasesProcessSlot() async {
        let worker = WorkerClient(
            prepareEnvironment: {},
            launchConfiguration: .init(
                executable: URL(fileURLWithPath: "/SaveMe-test-missing-executable"),
                arguments: [],
                runtime: "fixture"
            )
        )

        let first = await worker.run(request())
        let second = await worker.run(request())

        XCTAssertEqual(first.status, "process_error")
        XCTAssertEqual(second.status, "process_error")
        XCTAssertTrue(second.message.contains("Failed to launch worker"))
    }
}
