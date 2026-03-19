import Foundation

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

    func run() async throws -> String {
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
        environment["DIMASAVE_APP_SUPPORT"] = AppPaths.applicationSupport.path
        process.environment = environment

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdoutText = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdoutText.isEmpty ? "Среда подготовлена." : stdoutText)
                    return
                }

                let message = stderrText.isEmpty ? stdoutText : stderrText
                continuation.resume(throwing: BootstrapError.processFailed(message.isEmpty ? "Не удалось подготовить среду." : message))
            }

            do {
                try process.run()
            } catch {
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
