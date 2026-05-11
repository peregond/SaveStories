import Foundation

private final class BootstrapOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var output = ""
    private var hasResumed = false

    func append(_ data: Data, progress: @escaping @MainActor @Sendable (String) -> Void) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        lock.lock()
        output += text
        lock.unlock()

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            Task { @MainActor in
                progress(line)
            }
        }
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func markResumedIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}

struct WorkerBootstrapper {
    enum BootstrapError: LocalizedError {
        case bootstrapScriptNotFound
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .bootstrapScriptNotFound:
                "Не удалось найти встроенный скрипт подготовки среды."
            case .processFailed(let message):
                message
            }
        }
    }

    func run(progress: @escaping @MainActor @Sendable (String) -> Void = { _ in }) async throws -> String {
        try AppPaths.ensureDirectories()

        if AppPaths.hasEmbeddedRuntime {
            return "Встроенный движок уже находится внутри приложения. Дополнительная установка не нужна."
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [try bootstrapScriptURL().path]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["SAVESTORIES_APP_SUPPORT"] = AppPaths.applicationSupport.path
        process.environment = environment

        return try await withCheckedThrowingContinuation { continuation in
            let buffer = BootstrapOutputBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                buffer.append(handle.availableData, progress: progress)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                buffer.append(handle.availableData, progress: progress)
            }

            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                buffer.append(stdoutData, progress: progress)
                buffer.append(stderrData, progress: progress)
                let outputText = buffer.snapshot()

                guard buffer.markResumedIfNeeded() else {
                    return
                }

                if process.terminationStatus == 0 {
                    continuation.resume(returning: outputText.isEmpty ? "Среда подготовлена." : outputText)
                    return
                }

                continuation.resume(throwing: BootstrapError.processFailed(outputText.isEmpty ? "Не удалось подготовить среду." : outputText))
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                guard buffer.markResumedIfNeeded() else {
                    return
                }
                continuation.resume(throwing: BootstrapError.processFailed("Не удалось запустить подготовку среды: \(error.localizedDescription)"))
            }
        }
    }

    private func bootstrapScriptURL() throws -> URL {
        if let bundled = bundledResourceURL(relativePath: "bootstrap_worker.sh"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("bootstrap_node_worker.sh", isDirectory: false)

        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }

        throw BootstrapError.bootstrapScriptNotFound
    }

    private func bundledResourceURL(relativePath: String) -> URL? {
        let fileManager = FileManager.default
        let candidates = [
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
