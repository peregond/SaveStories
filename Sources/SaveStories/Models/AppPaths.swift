import Foundation

enum AppPaths {
    static let appName = "SaveMe"
    private static let legacyAppNames = ["SaveStories", "DimaSave"]
    private static let embeddedRuntimeDirectoryName = "runtime"
    private static let preservedWorkerEntryNames: Set<String> = [
        ".venv",
        "browser-profile",
        "ms-playwright",
        "node",
        "node_modules",
    ]
    private static let workerSourceSynchronizationLock = NSLock()
    static let resourceBundleName = "SaveMe_SaveMe.bundle"

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
        if let override = ProcessInfo.processInfo.environment["SAVESTORIES_APP_SUPPORT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return canWrite(to: preferredApplicationSupport.deletingLastPathComponent())
            ? preferredApplicationSupport
            : runtimeFallback
    }

    static var installedNodeWorkerRoot: URL? {
        let fileManager = FileManager.default
        let candidate = applicationSupport.appendingPathComponent("worker", isDirectory: true)
        let nodeWorker = candidate.appendingPathComponent("bridge.mjs", isDirectory: false)
        let nodeModules = candidate
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent("playwright", isDirectory: true)
        if fileManager.fileExists(atPath: nodeWorker.path) && fileManager.fileExists(atPath: nodeModules.path) {
            return candidate
        }

        return nil
    }

    static var installedWorkerRoot: URL? {
        if let installedNodeWorkerRoot {
            return installedNodeWorkerRoot
        }

        let candidate = applicationSupport.appendingPathComponent("worker", isDirectory: true)
        let python = candidate
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3", isDirectory: false)

        return FileManager.default.fileExists(atPath: python.path) ? candidate : nil
    }

    static var installedNodeExecutable: URL? {
        let candidates = [
            workerRoot
                .appendingPathComponent("node", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("node", isDirectory: false),
            installedWorkerRoot?
                .appendingPathComponent("node", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("node", isDirectory: false),
        ]

        return candidates.compactMap(existingFile(at:)).first
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

    static var bundledNodeExecutable: URL? {
        let candidates = [
            bundledRuntimeRoot?
                .appendingPathComponent("node", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("node", isDirectory: false),
            bundledRuntimeRoot?
                .appendingPathComponent("node", isDirectory: true)
                .appendingPathComponent("node", isDirectory: false),
        ]

        return candidates.compactMap(existingFile(at:)).first
    }

    static var bundledFrameworksDirectory: URL? {
        bundledFrameworksRoot
    }

    static var bundledMediaMuxerExecutable: URL? {
        let candidates = [
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("SaveMeMediaMuxer", isDirectory: false),
        ]

        return candidates.compactMap(existingFile(at:)).first
    }

    static var hasEmbeddedRuntime: Bool {
        (bundledNodeExecutable != nil && bundledPlaywrightBrowsers != nil)
            || (bundledPythonExecutable != nil && bundledSitePackages != nil && bundledPlaywrightBrowsers != nil)
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
        try migrateLegacyApplicationSupportIfNeeded(using: fileManager)
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

    /// Refreshes the installed worker sources from the copy shipped inside the app.
    /// Runtime dependencies and browser/session state are deliberately kept in place.
    @discardableResult
    static func synchronizeBundledNodeWorkerSources() throws -> Bool {
        workerSourceSynchronizationLock.lock()
        defer { workerSourceSynchronizationLock.unlock() }
        guard let bundledNodeWorkerRoot else { return false }
        return try synchronizeNodeWorkerSources(
            from: bundledNodeWorkerRoot,
            to: workerRoot,
            using: .default
        )
    }

    /// The injectable form is kept internal so the copy policy can be verified without
    /// touching the user's Application Support directory.
    @discardableResult
    static func synchronizeNodeWorkerSources(
        from sourceRoot: URL,
        to destinationRoot: URL,
        using fileManager: FileManager = .default
    ) throws -> Bool {
        let sourceRoot = sourceRoot.standardizedFileURL
        let destinationRoot = destinationRoot.standardizedFileURL
        guard sourceRoot != destinationRoot else { return false }

        for requiredFileName in ["package.json", "bridge.mjs"] {
            let requiredFile = sourceRoot.appendingPathComponent(requiredFileName, isDirectory: false)
            guard itemType(at: requiredFile, using: fileManager) == .typeRegular else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: requiredFile.path])
            }
        }

        if let bundledVersion = workerPackageVersion(at: sourceRoot, using: fileManager),
           let installedVersion = workerPackageVersion(at: destinationRoot, using: fileManager),
           compareVersion(installedVersion, to: bundledVersion) == .orderedDescending {
            return false
        }

        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: sourceRoot.path])
        }

        var didChange = false
        for case let sourceURL as URL in enumerator {
            guard let relativeComponents = relativePathComponents(of: sourceURL, under: sourceRoot),
                  let topLevelName = relativeComponents.first
            else {
                continue
            }

            if shouldPreserveInstalledWorkerEntry(named: topLevelName) || topLevelName == ".DS_Store" {
                enumerator.skipDescendants()
                continue
            }

            let values = try sourceURL.resourceValues(forKeys: Set(resourceKeys))
            guard values.isSymbolicLink != true else {
                throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSFilePathErrorKey: sourceURL.path])
            }

            let destinationURL = relativeComponents.reduce(destinationRoot) { partialResult, component in
                partialResult.appendingPathComponent(component, isDirectory: false)
            }

            if values.isDirectory == true {
                if itemType(at: destinationURL, using: fileManager) != .typeDirectory {
                    try removeItemIfPresent(at: destinationURL, using: fileManager)
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                    didChange = true
                }
                continue
            }

            guard values.isRegularFile == true else { continue }
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let destinationType = itemType(at: destinationURL, using: fileManager)
            if destinationType == .typeRegular,
               fileManager.contentsEqual(atPath: sourceURL.path, andPath: destinationURL.path) {
                continue
            }

            if destinationType != nil, destinationType != .typeRegular {
                try fileManager.removeItem(at: destinationURL)
            }

            let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            try data.write(to: destinationURL, options: [.atomic])
            if let permissions = try fileManager.attributesOfItem(atPath: sourceURL.path)[.posixPermissions] {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: destinationURL.path)
            }
            didChange = true
        }

        guard let destinationEnumerator = fileManager.enumerator(
            at: destinationRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: destinationRoot.path])
        }

        var staleItems: [URL] = []
        for case let destinationURL as URL in destinationEnumerator {
            guard let relativeComponents = relativePathComponents(of: destinationURL, under: destinationRoot),
                  let topLevelName = relativeComponents.first
            else {
                continue
            }

            if shouldPreserveInstalledWorkerEntry(named: topLevelName) {
                destinationEnumerator.skipDescendants()
                continue
            }

            let sourceURL = relativeComponents.reduce(sourceRoot) { partialResult, component in
                partialResult.appendingPathComponent(component, isDirectory: false)
            }
            guard itemType(at: sourceURL, using: fileManager) == nil || topLevelName == ".DS_Store" else {
                continue
            }

            staleItems.append(destinationURL)
            if itemType(at: destinationURL, using: fileManager) == .typeDirectory {
                destinationEnumerator.skipDescendants()
            }
        }

        for staleItem in staleItems.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            try removeItemIfPresent(at: staleItem, using: fileManager)
            didChange = true
        }

        return didChange
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

    private static var bundledNodeWorkerRoot: URL? {
        let candidates = [
            Bundle.main.sharedSupportURL?
                .appendingPathComponent("node_worker", isDirectory: true),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("SharedSupport", isDirectory: true)
                .appendingPathComponent("node_worker", isDirectory: true),
        ]

        return candidates
            .compactMap { $0 }
            .first(where: { candidate in
                existingFile(at: candidate.appendingPathComponent("package.json", isDirectory: false)) != nil
                    && existingFile(at: candidate.appendingPathComponent("bridge.mjs", isDirectory: false)) != nil
            })
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

    private static var legacyApplicationSupports: [URL] {
        legacyAppNames.map { legacyName in
            homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent(legacyName, isDirectory: true)
        }
    }

    private static func migrateLegacyApplicationSupportIfNeeded(using fileManager: FileManager) throws {
        guard applicationSupport.lastPathComponent == appName else { return }
        guard !fileManager.fileExists(atPath: applicationSupport.path) else { return }
        guard let legacySource = legacyApplicationSupports.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return
        }

        try fileManager.createDirectory(
            at: applicationSupport.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: legacySource, to: applicationSupport)
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

    private static func relativePathComponents(of item: URL, under root: URL) -> [String]? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let itemComponents = item.standardizedFileURL.pathComponents
        guard itemComponents.count > rootComponents.count,
              itemComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
        else {
            return nil
        }

        return Array(itemComponents.dropFirst(rootComponents.count))
    }

    private static func shouldPreserveInstalledWorkerEntry(named name: String) -> Bool {
        preservedWorkerEntryNames.contains(name) || name.hasPrefix("storage-state")
    }

    private static func itemType(at url: URL, using fileManager: FileManager) -> FileAttributeType? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType
    }

    private static func removeItemIfPresent(at url: URL, using fileManager: FileManager) throws {
        guard itemType(at: url, using: fileManager) != nil else { return }
        try fileManager.removeItem(at: url)
    }

    private static func workerPackageVersion(at root: URL, using fileManager: FileManager) -> [Int]? {
        let packageURL = root.appendingPathComponent("package.json", isDirectory: false)
        guard itemType(at: packageURL, using: fileManager) == .typeRegular,
              let data = try? Data(contentsOf: packageURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = payload["version"] as? String
        else {
            return nil
        }

        let components = version.split(separator: ".").compactMap { component -> Int? in
            let digits = component.prefix(while: { $0.isNumber })
            return digits.isEmpty ? nil : Int(digits)
        }
        return components.isEmpty ? nil : components
    }

    private static func compareVersion(_ left: [Int], to right: [Int]) -> ComparisonResult {
        let count = max(left.count, right.count)
        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }
}
