import Foundation

struct FileDistributionInput: Sendable {
    let id: String
    let originalUsername: String
    let currentURL: URL
    let targetRelativeFolder: String
}

struct FileDistributionRecord: Sendable {
    let id: String
    let originalUsername: String
    let targetRelativeFolder: String
    let originalURL: URL
    let currentURL: URL
}

struct FileDistributionScanResult: Sendable {
    let inputs: [FileDistributionInput]
    let unreadableFolderNames: [String]
}

struct FileDistributionResult: Sendable {
    let records: [FileDistributionRecord]
    let movedCount: Int
    let failedFileNames: [String]
}

struct FileDistributionUndoInput: Sendable {
    let id: String
    let currentURL: URL
    let originalURL: URL
}

struct FileDistributionUndoRecord: Sendable {
    let id: String
    let restoredURL: URL
}

struct FileDistributionUndoResult: Sendable {
    let restoredRecords: [FileDistributionUndoRecord]
    let failedIDs: Set<String>
    let failedFileNames: [String]
}

enum FileDistributionService {
    enum DistributionError: LocalizedError {
        case sourceUnreadable
        case unsafeDestination(String)

        var errorDescription: String? {
            switch self {
            case .sourceUnreadable:
                "Не удалось прочитать содержимое папки источника."
            case .unsafeDestination(let folder):
                "Правило сортировки содержит небезопасный путь: \(folder)."
            }
        }
    }

    static func targetRelativeFolderPath(for username: String, mapping: [String: String]) -> String {
        guard let mapped = mapping[username.lowercased()]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mapped.isEmpty,
              let components = safePathComponents(from: mapped),
              !components.isEmpty
        else {
            return username
        }

        if components.count == 1 {
            return components[0] + "/" + username
        }

        return components.joined(separator: "/")
    }

    static func scanInputs(in sourceDirectory: URL, mapping: [String: String]) throws -> FileDistributionScanResult {
        let manager = FileManager.default
        guard let creatorFolders = try? manager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DistributionError.sourceUnreadable
        }

        var inputs: [FileDistributionInput] = []
        var unreadableFolderNames: [String] = []

        for creatorFolder in creatorFolders.sorted(by: standardURLSort) {
            let values = try? creatorFolder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

            let creatorName = creatorFolder.lastPathComponent
            guard let files = try? manager.contentsOfDirectory(
                at: creatorFolder,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                unreadableFolderNames.append(creatorName)
                continue
            }

            let targetFolder = targetRelativeFolderPath(for: creatorName, mapping: mapping)
            for candidate in files.sorted(by: standardURLSort) {
                let candidateValues = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard candidateValues?.isRegularFile == true, candidateValues?.isSymbolicLink != true else { continue }
                inputs.append(
                    FileDistributionInput(
                        id: candidate.standardizedFileURL.path,
                        originalUsername: creatorName,
                        currentURL: candidate,
                        targetRelativeFolder: targetFolder
                    )
                )
            }
        }

        return FileDistributionScanResult(inputs: inputs, unreadableFolderNames: unreadableFolderNames)
    }

    static func distribute(inputs: [FileDistributionInput], destinationRoot: URL) -> FileDistributionResult {
        let manager = FileManager.default
        var records: [FileDistributionRecord] = []
        var movedCount = 0
        var failedFileNames: [String] = []

        do {
            try manager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        } catch {
            return FileDistributionResult(
                records: [],
                movedCount: 0,
                failedFileNames: inputs.map { $0.currentURL.lastPathComponent }
            )
        }

        for input in inputs {
            guard isRegularFile(input.currentURL, fileManager: manager) else {
                failedFileNames.append(input.currentURL.lastPathComponent)
                continue
            }

            do {
                let destinationDirectory = try safeDestinationDirectory(
                    relativePath: input.targetRelativeFolder,
                    destinationRoot: destinationRoot
                )
                try manager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

                let directDestination = destinationDirectory.appendingPathComponent(
                    input.currentURL.lastPathComponent,
                    isDirectory: false
                )
                let destinationURL = input.currentURL.standardizedFileURL == directDestination.standardizedFileURL
                    ? input.currentURL
                    : uniqueDestinationURL(
                        for: input.currentURL.lastPathComponent,
                        in: destinationDirectory,
                        fileManager: manager
                    )

                if input.currentURL.standardizedFileURL != destinationURL.standardizedFileURL {
                    try manager.moveItem(at: input.currentURL, to: destinationURL)
                    movedCount += 1
                }

                records.append(
                    FileDistributionRecord(
                        id: input.id,
                        originalUsername: input.originalUsername,
                        targetRelativeFolder: input.targetRelativeFolder,
                        originalURL: input.currentURL,
                        currentURL: destinationURL
                    )
                )
            } catch {
                failedFileNames.append(input.currentURL.lastPathComponent)
            }
        }

        return FileDistributionResult(
            records: records,
            movedCount: movedCount,
            failedFileNames: failedFileNames
        )
    }

    static func undo(_ inputs: [FileDistributionUndoInput]) -> FileDistributionUndoResult {
        let manager = FileManager.default
        var restoredRecords: [FileDistributionUndoRecord] = []
        var failedIDs = Set<String>()
        var failedFileNames: [String] = []

        for input in inputs.reversed() {
            guard isRegularFile(input.currentURL, fileManager: manager) else {
                failedIDs.insert(input.id)
                failedFileNames.append(input.currentURL.lastPathComponent)
                continue
            }

            do {
                try manager.createDirectory(
                    at: input.originalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                let restoredURL = manager.fileExists(atPath: input.originalURL.path)
                    && input.currentURL.standardizedFileURL != input.originalURL.standardizedFileURL
                    ? uniqueDestinationURL(
                        for: input.originalURL.lastPathComponent,
                        in: input.originalURL.deletingLastPathComponent(),
                        fileManager: manager
                    )
                    : input.originalURL

                if input.currentURL.standardizedFileURL != restoredURL.standardizedFileURL {
                    try manager.moveItem(at: input.currentURL, to: restoredURL)
                }
                restoredRecords.append(FileDistributionUndoRecord(id: input.id, restoredURL: restoredURL))
            } catch {
                failedIDs.insert(input.id)
                failedFileNames.append(input.currentURL.lastPathComponent)
            }
        }

        return FileDistributionUndoResult(
            restoredRecords: restoredRecords,
            failedIDs: failedIDs,
            failedFileNames: failedFileNames
        )
    }

    private static func safePathComponents(from rawPath: String) -> [String]? {
        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("\0") })
        else {
            return nil
        }
        return components
    }

    private static func safeDestinationDirectory(relativePath: String, destinationRoot: URL) throws -> URL {
        guard let components = safePathComponents(from: relativePath), !components.isEmpty else {
            throw DistributionError.unsafeDestination(relativePath)
        }

        let root = destinationRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"

        var candidate = root
        for component in components {
            candidate.appendPathComponent(component, isDirectory: true)
            if let values = try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]),
               values.isSymbolicLink == true {
                throw DistributionError.unsafeDestination(relativePath)
            }

            let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedCandidate.path == root.path || resolvedCandidate.path.hasPrefix(rootPath) else {
                throw DistributionError.unsafeDestination(relativePath)
            }
            candidate = resolvedCandidate
        }

        return candidate
    }

    private static func uniqueDestinationURL(for filename: String, in directory: URL, fileManager: FileManager) -> URL {
        let candidate = directory.appendingPathComponent(filename, isDirectory: false)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        let numberedName = splitTrailingNumber(from: stem)
        var index = numberedName.nextNumber

        while true {
            let adjustedStem = numberedName.prefix + formattedNumber(index, width: numberedName.width)
            let adjustedName = ext.isEmpty ? adjustedStem : "\(adjustedStem).\(ext)"
            let adjustedURL = directory.appendingPathComponent(adjustedName, isDirectory: false)
            if !fileManager.fileExists(atPath: adjustedURL.path) {
                return adjustedURL
            }
            index += 1
        }
    }

    private static func splitTrailingNumber(from stem: String) -> (prefix: String, nextNumber: Int, width: Int) {
        guard let range = stem.range(of: #"\d+$"#, options: .regularExpression) else {
            return ("\(stem) ", 2, 0)
        }

        let numberText = String(stem[range])
        let prefix = String(stem[..<range.lowerBound])
        return (prefix, (Int(numberText) ?? 1) + 1, numberText.count)
    }

    private static func formattedNumber(_ number: Int, width: Int) -> String {
        guard width > 0 else { return "\(number)" }
        return String(format: "%0\(width)d", number)
    }

    private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
            .map { $0.isRegularFile == true && $0.isSymbolicLink != true } ?? false
    }

    private static func standardURLSort(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
    }
}
