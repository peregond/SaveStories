import Foundation

struct EmptyFolderCleanupResult {
    let removedFolders: [URL]
    let failedFolders: [URL]

    var removedFolderNames: [String] {
        removedFolders
            .map(\.lastPathComponent)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum EmptyFolderCleanupService {
    static func findDeletableEmptyFolders(in root: URL) -> [URL] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [],
                errorHandler: nil
              )
        else {
            return []
        }

        var candidates: [URL] = []
        for case let item as URL in enumerator {
            if isProtectedTransferDirectory(item) {
                enumerator.skipDescendants()
                continue
            }

            guard isDirectoryURL(item) else { continue }
            candidates.append(item.standardizedFileURL)
        }

        let sorted = candidates.sorted { directoryDepth($0) > directoryDepth($1) }
        var knownEmptyDirectories = Set<String>()
        for folder in sorted {
            if isEffectivelyEmptyDirectoryAfterDeletingKnownEmptyChildren(
                folder,
                knownEmptyDirectories: knownEmptyDirectories
            ) {
                knownEmptyDirectories.insert(folder.standardizedFileURL.path)
            }
        }

        return sorted.filter { knownEmptyDirectories.contains($0.standardizedFileURL.path) }
    }

    static func deleteEmptyFolders(_ folders: [URL]) -> EmptyFolderCleanupResult {
        let manager = FileManager.default
        var removed: [URL] = []
        var failed: [URL] = []

        for folder in folders
            .map(\.standardizedFileURL)
            .filter({ !isProtectedTransferDirectory($0) })
            .sorted(by: { directoryDepth($0) > directoryDepth($1) }) {
            guard manager.fileExists(atPath: folder.path) else { continue }

            do {
                if isEffectivelyEmptyDirectory(folder) {
                    try manager.removeItem(at: folder)
                    removed.append(folder)
                }
            } catch {
                failed.append(folder)
            }
        }

        return EmptyFolderCleanupResult(removedFolders: removed, failedFolders: failed)
    }

    static func isIgnorableFilesystemEntry(_ url: URL) -> Bool {
        let ignoredNames = [".DS_Store", "desktop.ini", "Thumbs.db"]
        return ignoredNames.contains { ignored in
            url.lastPathComponent.caseInsensitiveCompare(ignored) == .orderedSame
        }
    }

    private static func isEffectivelyEmptyDirectoryAfterDeletingKnownEmptyChildren(
        _ directory: URL,
        knownEmptyDirectories: Set<String>
    ) -> Bool {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return false
        }

        for entry in children {
            if isIgnorableFilesystemEntry(entry) {
                continue
            }

            if isDirectoryURL(entry),
               knownEmptyDirectories.contains(entry.standardizedFileURL.path) {
                continue
            }

            return false
        }

        return true
    }

    private static func isEffectivelyEmptyDirectory(_ directory: URL) -> Bool {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return false
        }

        for entry in children where !isIgnorableFilesystemEntry(entry) {
            return false
        }

        return true
    }

    private static func isProtectedTransferDirectory(_ url: URL) -> Bool {
        url.pathComponents.contains { component in
            component.caseInsensitiveCompare("На перенос") == .orderedSame
        }
    }

    private static func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func directoryDepth(_ url: URL) -> Int {
        url.standardizedFileURL.pathComponents.count
    }
}
