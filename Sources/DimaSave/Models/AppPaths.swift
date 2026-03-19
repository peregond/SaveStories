import Foundation

enum AppPaths {
    static let appName = "DimaSave"
    private static let embeddedRuntimeDirectoryName = "runtime"
    private static let resourceBundleName = "DimaSave_DimaSave.bundle"

    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private static var preferredApplicationSupport: URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    private static var runtimeFallback: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".runtime", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    private static func canWrite(to directory: URL) -> Bool {
        let fileManager = FileManager.default
        var candidate = directory

        while candidate.path != "/" {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue && fileManager.isWritableFile(atPath: candidate.path)
            }
            candidate.deleteLastPathComponent()
        }

        return false
    }

    static var applicationSupport: URL {
        if let override = ProcessInfo.processInfo.environment["DIMASAVE_APP_SUPPORT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return canWrite(to: preferredApplicationSupport.deletingLastPathComponent())
            ? preferredApplicationSupport
            : runtimeFallback
    }

    private static var installedWorkerRoot: URL? {
        let fileManager = FileManager.default
        let candidate = preferredApplicationSupport.appendingPathComponent("worker", isDirectory: true)
        let python = candidate
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3", isDirectory: false)

        return fileManager.fileExists(atPath: python.path) ? candidate : nil
    }

    static var workerRoot: URL {
        applicationSupport.appendingPathComponent("worker", isDirectory: true)
    }

    static var workerVenvRoot: URL {
        (installedWorkerRoot ?? workerRoot).appendingPathComponent(".venv", isDirectory: true)
    }

    static var workerPython: URL {
        if let bundled = bundledPythonExecutable {
            return bundled
        }

        return workerVenvRoot
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3", isDirectory: false)
    }

    static var browserProfile: URL {
        workerRoot.appendingPathComponent("browser-profile", isDirectory: true)
    }

    static var manifestsDirectory: URL {
        applicationSupport.appendingPathComponent("manifests", isDirectory: true)
    }

    static var playwrightBrowsers: URL {
        if let bundled = bundledPlaywrightBrowsers {
            return bundled
        }

        return (installedWorkerRoot ?? workerRoot).appendingPathComponent("ms-playwright", isDirectory: true)
    }

    static var bundledPythonHome: URL? {
        guard let versionsDirectory = bundledFrameworksRoot?
            .appendingPathComponent("Python.framework", isDirectory: true)
            .appendingPathComponent("Versions", isDirectory: true),
              let versionsRoot = existingDirectory(at: versionsDirectory),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: versionsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return nil
        }

        let candidates = entries
            .filter { $0.lastPathComponent != "Current" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }

        return candidates.compactMap(existingDirectory(at:)).first
    }

    static var bundledPythonExecutable: URL? {
        guard let binDirectory = bundledPythonHome?
            .appendingPathComponent("bin", isDirectory: true),
              let binRoot = existingDirectory(at: binDirectory)
        else {
            return nil
        }

        let preferred = existingFile(at: binRoot.appendingPathComponent("python3", isDirectory: false))
        if let preferred {
            return preferred
        }

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: binRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = entries
            .filter { $0.lastPathComponent.hasPrefix("python3") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }

        return candidates.compactMap(existingFile(at:)).first
    }

    static var bundledSitePackages: URL? {
        let path = bundledRuntimeRoot?
            .appendingPathComponent("site-packages", isDirectory: true)

        return existingDirectory(at: path)
    }

    static var bundledPlaywrightBrowsers: URL? {
        let path = bundledRuntimeRoot?
            .appendingPathComponent("ms-playwright", isDirectory: true)

        return existingDirectory(at: path)
    }

    static var bundledFrameworksDirectory: URL? {
        bundledFrameworksRoot
    }

    static var hasEmbeddedRuntime: Bool {
        bundledPythonExecutable != nil && bundledSitePackages != nil && bundledPlaywrightBrowsers != nil
    }

    static var logsDirectory: URL {
        applicationSupport.appendingPathComponent("logs", isDirectory: true)
    }

    static var defaultDownloads: URL {
        let preferred = homeDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)

        return canWrite(to: preferred.deletingLastPathComponent())
            ? preferred
            : applicationSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    static func ensureDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workerRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: browserProfile, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: manifestsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: defaultDownloads, withIntermediateDirectories: true)

        if bundledPlaywrightBrowsers == nil {
            try fileManager.createDirectory(at: playwrightBrowsers, withIntermediateDirectories: true)
        }
    }

    private static var bundledFrameworksRoot: URL? {
        let candidates = [
            Bundle.main.privateFrameworksURL,
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Frameworks", isDirectory: true),
        ]

        return candidates.compactMap(existingDirectory(at:)).first
    }

    private static var bundledRuntimeRoot: URL? {
        let candidates = [
            Bundle.main.sharedSupportURL?
                .appendingPathComponent(embeddedRuntimeDirectoryName, isDirectory: true),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("SharedSupport", isDirectory: true)
                .appendingPathComponent(embeddedRuntimeDirectoryName, isDirectory: true),
            Bundle.main.resourceURL?
                .appendingPathComponent(resourceBundleName, isDirectory: true)
                .appendingPathComponent(embeddedRuntimeDirectoryName, isDirectory: true),
        ]

        return candidates.compactMap(existingDirectory(at:)).first
    }

    private static func existingDirectory(at url: URL?) -> URL? {
        guard let url else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return url
    }

    private static func existingFile(at url: URL?) -> URL? {
        guard let url else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return url
    }
}
