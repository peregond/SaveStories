import Foundation

@MainActor
final class WorkerClient {
    struct LaunchConfiguration {
        let executable: URL
        let arguments: [String]
        let runtime: String
    }

    private final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var completed = false
        private var inputFailure: String?

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return false }
            completed = true
            return true
        }

        func recordInputFailure(_ message: String) {
            lock.lock()
            defer { lock.unlock() }
            inputFailure = message
        }

        func inputFailureMessage() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return inputFailure
        }
    }

    private final class PipeCollector: @unchecked Sendable {
        private let fileHandle: FileHandle
        private let onLine: (@Sendable (String) -> Void)?
        private let lock = NSLock()
        private let finished = DispatchSemaphore(value: 0)
        private var collectedData = Data()
        private var readerThread: Thread?

        init(fileHandle: FileHandle, onLine: (@Sendable (String) -> Void)? = nil) {
            self.fileHandle = fileHandle
            self.onLine = onLine
        }

        func start() {
            guard readerThread == nil else { return }

            let thread = Thread { [fileHandle, onLine] in
                var completeData = Data()
                var partialLine = Data()

                while true {
                    let chunk = fileHandle.availableData
                    if chunk.isEmpty {
                        break
                    }

                    completeData.append(chunk)

                    guard let onLine else { continue }
                    partialLine.append(chunk)

                    while let newlineIndex = partialLine.firstIndex(of: 0x0A) {
                        let lineData = partialLine.prefix(upTo: newlineIndex)
                        partialLine.removeSubrange(...newlineIndex)
                        if let line = String(data: lineData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !line.isEmpty
                        {
                            onLine(line)
                        }
                    }
                }

                if let onLine,
                   let trailing = String(data: partialLine, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !trailing.isEmpty
                {
                    onLine(trailing)
                }

                self.lock.lock()
                self.collectedData = completeData
                self.lock.unlock()
                self.finished.signal()
            }
            thread.name = "SaveMe.PipeCollector"
            thread.start()
            readerThread = thread
        }

        func finish(timeout: TimeInterval = 5.0) -> Data {
            _ = finished.wait(timeout: .now() + timeout)
            lock.lock()
            defer { lock.unlock() }
            return collectedData
        }
    }

    enum WorkerClientError: LocalizedError {
        case workerScriptNotFound
        case processLaunchFailed(String)
        case invalidWorkerResponse(byteCount: Int)

        var errorDescription: String? {
            switch self {
            case .workerScriptNotFound:
                "Worker script was not found in the package resources."
            case .processLaunchFailed(let message):
                message
            case .invalidWorkerResponse(let byteCount):
                "Worker вернул некорректный JSON (\(byteCount) байт). Попробуйте повторить операцию или подготовить среду заново."
            }
        }
    }

    private var currentProcess: Process?
    private var userInitiatedStop = false
    private let prepareEnvironment: () throws -> Void
    private let launchConfigurationOverride: LaunchConfiguration?

    init(
        prepareEnvironment: @escaping () throws -> Void = {
            try AppPaths.ensureDirectories()
            try AppPaths.synchronizeBundledNodeWorkerSources()
        },
        launchConfiguration: LaunchConfiguration? = nil
    ) {
        self.prepareEnvironment = prepareEnvironment
        self.launchConfigurationOverride = launchConfiguration
    }

    func run(_ request: WorkerRequest, onProgress: (@Sendable (String) -> Void)? = nil) async -> WorkerResponse {
        guard currentProcess == nil else {
            return .processFailure(message: "Worker уже выполняет другую операцию. Дождитесь её завершения.")
        }
        guard !Task.isCancelled else {
            return .cancelled(message: "Операция отменена.")
        }
        defer {
            currentProcess = nil
            userInitiatedStop = false
        }

        do {
            let response = try await execute(request, onProgress: onProgress)
            if userInitiatedStop || Task.isCancelled {
                return .cancelled(message: "Загрузка остановлена пользователем.")
            }
            return response
        } catch {
            if userInitiatedStop || Task.isCancelled {
                return .cancelled(message: "Загрузка остановлена пользователем.")
            }
            return .processFailure(message: error.localizedDescription)
        }
    }

    func stopCurrentProcess() {
        guard let currentProcess, currentProcess.isRunning else { return }
        userInitiatedStop = true
        currentProcess.terminate()
    }

    private func execute(_ request: WorkerRequest, onProgress: (@Sendable (String) -> Void)? = nil) async throws -> WorkerResponse {
        try prepareEnvironment()
        var encodedRequest = try JSONEncoder().encode(request)
        encodedRequest.append(0x0A)

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCollector = PipeCollector(fileHandle: stdoutPipe.fileHandleForReading)
        let stderrCollector = PipeCollector(fileHandle: stderrPipe.fileHandleForReading, onLine: onProgress)

        let launch = try launchConfigurationOverride ?? workerLaunchConfiguration()
        process.executableURL = launch.executable
        process.arguments = launch.arguments

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["SAVESTORIES_APP_SUPPORT"] = AppPaths.applicationSupport.path
        environment["SAVESTORIES_BROWSER_PROFILE"] = AppPaths.browserProfile.path
        environment["SAVESTORIES_MANIFESTS"] = AppPaths.manifestsDirectory.path
        environment["SAVESTORIES_PLAYWRIGHT_BROWSERS"] = AppPaths.playwrightBrowsers.path
        environment["SAVESTORIES_DEFAULT_DOWNLOADS"] = AppPaths.defaultDownloads.path
        environment["SAVESTORIES_LOGS"] = AppPaths.logsDirectory.path
        environment["SAVESTORIES_WORKER_RUNTIME"] = launch.runtime
        if let mediaMuxer = AppPaths.bundledMediaMuxerExecutable {
            environment["SAVEME_MEDIA_MUXER"] = mediaMuxer.path
        }
        if let bundledFrameworks = AppPaths.bundledFrameworksDirectory {
            environment["DYLD_FRAMEWORK_PATH"] = bundledFrameworks.path
        }
        if launch.runtime == "python", let bundledPythonHome = AppPaths.bundledPythonHome {
            environment["PYTHONHOME"] = bundledPythonHome.path
            environment["PYTHONNOUSERSITE"] = "1"
        }
        if launch.runtime == "python", let bundledSitePackages = AppPaths.bundledSitePackages {
            environment["PYTHONPATH"] = bundledSitePackages.path
        }
        process.environment = environment
        currentProcess = process

        let responseData: Data = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
            let completionGate = CompletionGate()

            process.terminationHandler = { process in
                let stdoutData = stdoutCollector.finish()
                let stderrData = stderrCollector.finish()
                guard completionGate.claim() else { return }
                if let inputFailure = completionGate.inputFailureMessage() {
                    continuation.resume(throwing: WorkerClientError.processLaunchFailed(inputFailure))
                    return
                }

                if process.terminationStatus != 0 && stdoutData.isEmpty {
                    let stderrText = String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let reason: String
                    switch process.terminationReason {
                    case .exit:
                        reason = "exit status \(process.terminationStatus)"
                    case .uncaughtSignal:
                        reason = "signal \(process.terminationStatus)"
                    @unknown default:
                        reason = "unknown termination \(process.terminationStatus)"
                    }

                    let message: String
                    if let stderrText, !stderrText.isEmpty {
                        message = "\(stderrText)\n[\(reason)]"
                    } else {
                        message = "Worker process failed with \(reason)."
                    }
                    continuation.resume(throwing: WorkerClientError.processLaunchFailed(message))
                    return
                }

                if stdoutData.isEmpty {
                    let stderrText = String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let message: String
                    if let stderrText, !stderrText.isEmpty {
                        message = stderrText
                    } else {
                        message = "Worker returned no output."
                    }
                    continuation.resume(throwing: WorkerClientError.processLaunchFailed(message))
                    return
                }

                continuation.resume(returning: stdoutData)
            }

            do {
                try process.run()
                stdoutCollector.start()
                stderrCollector.start()
            } catch {
                guard completionGate.claim() else { return }
                continuation.resume(
                    throwing: WorkerClientError.processLaunchFailed("Failed to launch worker: \(error.localizedDescription)")
                )
                return
            }

            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: encodedRequest)
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                completionGate.recordInputFailure("Failed to send request to worker: \(error.localizedDescription)")
                try? stdinPipe.fileHandleForWriting.close()
                if process.isRunning {
                    process.terminate()
                }
            }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.currentProcess === process else { return }
                self?.stopCurrentProcess()
            }
        }

        do {
            return try JSONDecoder().decode(WorkerResponse.self, from: responseData)
        } catch {
            throw WorkerClientError.invalidWorkerResponse(byteCount: responseData.count)
        }
    }

    private func workerLaunchConfiguration() throws -> LaunchConfiguration {
        if let nodeScript = nodeWorkerScriptURL(),
           let installedNode = AppPaths.installedNodeExecutable {
            return LaunchConfiguration(executable: installedNode, arguments: [nodeScript.path], runtime: "node")
        }

        if let nodeScript = nodeWorkerScriptURL(),
           let bundledNode = AppPaths.bundledNodeExecutable {
            return LaunchConfiguration(executable: bundledNode, arguments: [nodeScript.path], runtime: "node")
        }

        if let nodeScript = nodeWorkerScriptURL(),
           let nodeExecutable = locateExecutable(named: "node") {
            return LaunchConfiguration(executable: nodeExecutable, arguments: [nodeScript.path], runtime: "node")
        }

        throw WorkerClientError.processLaunchFailed("Node runtime не найден. Подготовьте среду воркера в настройках приложения.")
    }

    private func nodeWorkerScriptURL() -> URL? {
        let installedScript = AppPaths.installedNodeWorkerRoot?
            .appendingPathComponent("bridge.mjs", isDirectory: false)
        let fallbackInstalledScript = AppPaths.workerRoot
            .appendingPathComponent("bridge.mjs", isDirectory: false)
        let candidates = [
            installedScript,
            Bundle.main.sharedSupportURL?
                .appendingPathComponent("node_worker", isDirectory: true)
                .appendingPathComponent("bridge.mjs", isDirectory: false),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("SharedSupport", isDirectory: true)
                .appendingPathComponent("node_worker", isDirectory: true)
                .appendingPathComponent("bridge.mjs", isDirectory: false),
            fallbackInstalledScript,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("node_worker", isDirectory: true)
                .appendingPathComponent("bridge.mjs", isDirectory: false),
        ]

        return candidates
            .compactMap { $0 }
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private func pythonWorkerScriptURL() throws -> URL {
        if let bundled = bundledResourceURL(relativePath: "worker/bridge.py"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        let fallbackCandidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("SaveMe", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("worker", isDirectory: true)
                .appendingPathComponent("bridge.py", isDirectory: false),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("SaveStories", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("worker", isDirectory: true)
                .appendingPathComponent("bridge.py", isDirectory: false),
        ]

        if let fallback = fallbackCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return fallback
        }

        throw WorkerClientError.workerScriptNotFound
    }

    private func locateExecutable(named executable: String) -> URL? {
        let pathVariable = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for component in pathVariable.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(component), isDirectory: true)
                .appendingPathComponent(executable, isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func bundledResourceURL(relativePath: String) -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent(AppPaths.resourceBundleName, isDirectory: true)
                .appendingPathComponent("Contents/Resources", isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false),
            Bundle.main.resourceURL?
                .appendingPathComponent(AppPaths.resourceBundleName, isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(AppPaths.resourceBundleName, isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false),
        ]

        return candidates
            .compactMap { $0 }
            .first(where: { fileManager.fileExists(atPath: $0.path) })
    }
}
