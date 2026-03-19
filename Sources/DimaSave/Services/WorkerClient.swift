import Foundation

@MainActor
final class WorkerClient {
    enum WorkerClientError: LocalizedError {
        case workerScriptNotFound
        case processLaunchFailed(String)
        case invalidWorkerResponse(String)

        var errorDescription: String? {
            switch self {
            case .workerScriptNotFound:
                "Worker script was not found in the package resources."
            case .processLaunchFailed(let message):
                message
            case .invalidWorkerResponse(let raw):
                "Worker returned invalid JSON.\n\(raw)"
            }
        }
    }

    private var currentProcess: Process?
    private var userInitiatedStop = false

    func run(_ request: WorkerRequest) async -> WorkerResponse {
        do {
            let response = try await execute(request)
            if userInitiatedStop {
                userInitiatedStop = false
                return .cancelled(message: "Загрузка остановлена пользователем.")
            }
            return response
        } catch {
            if userInitiatedStop {
                userInitiatedStop = false
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

    private func execute(_ request: WorkerRequest) async throws -> WorkerResponse {
        try AppPaths.ensureDirectories()

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let launch = try workerLaunchConfiguration()
        process.executableURL = launch.executable
        process.arguments = launch.arguments

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["DIMASAVE_APP_SUPPORT"] = AppPaths.applicationSupport.path
        environment["DIMASAVE_BROWSER_PROFILE"] = AppPaths.browserProfile.path
        environment["DIMASAVE_MANIFESTS"] = AppPaths.manifestsDirectory.path
        environment["DIMASAVE_PLAYWRIGHT_BROWSERS"] = AppPaths.playwrightBrowsers.path
        environment["DIMASAVE_DEFAULT_DOWNLOADS"] = AppPaths.defaultDownloads.path
        environment["DIMASAVE_WORKER_RUNTIME"] = launch.runtime
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

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                Task { @MainActor in
                    self.currentProcess = nil
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
            } catch {
                continuation.resume(
                    throwing: WorkerClientError.processLaunchFailed("Failed to launch worker: \(error.localizedDescription)")
                )
                return
            }

            do {
                let encoded = try JSONEncoder().encode(request)
                stdinPipe.fileHandleForWriting.write(encoded)
                stdinPipe.fileHandleForWriting.write(Data([0x0A]))
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                process.terminate()
                continuation.resume(
                    throwing: WorkerClientError.processLaunchFailed("Failed to send request to worker: \(error.localizedDescription)")
                )
            }
        }

        do {
            return try JSONDecoder().decode(WorkerResponse.self, from: responseData)
        } catch {
            let raw = String(data: responseData, encoding: .utf8) ?? "<non-utf8 response>"
            throw WorkerClientError.invalidWorkerResponse(raw)
        }
    }

    private func workerLaunchConfiguration() throws -> (executable: URL, arguments: [String], runtime: String) {
        if let nodeScript = nodeWorkerScriptURL(),
           let bundledNode = AppPaths.bundledNodeExecutable {
            return (bundledNode, [nodeScript.path], "node")
        }

        if let nodeScript = nodeWorkerScriptURL(),
           let nodeExecutable = locateExecutable(named: "node") {
            return (nodeExecutable, [nodeScript.path], "node")
        }

        let scriptURL = try pythonWorkerScriptURL()
        if FileManager.default.isExecutableFile(atPath: AppPaths.workerPython.path) {
            return (AppPaths.workerPython, [scriptURL.path], "python")
        }

        return (URL(fileURLWithPath: "/usr/bin/env"), ["python3", scriptURL.path], "python")
    }

    private func nodeWorkerScriptURL() -> URL? {
        let candidates = [
            Bundle.main.sharedSupportURL?
                .appendingPathComponent("node_worker", isDirectory: true)
                .appendingPathComponent("bridge.mjs", isDirectory: false),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("SharedSupport", isDirectory: true)
                .appendingPathComponent("node_worker", isDirectory: true)
                .appendingPathComponent("bridge.mjs", isDirectory: false),
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

        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("DimaSave", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("worker", isDirectory: true)
            .appendingPathComponent("bridge.py", isDirectory: false)

        if FileManager.default.fileExists(atPath: fallback.path) {
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
                .appendingPathComponent("DimaSave_DimaSave.bundle", isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("DimaSave_DimaSave.bundle", isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: false),
        ]

        return candidates
            .compactMap { $0 }
            .first(where: { fileManager.fileExists(atPath: $0.path) })
    }
}
