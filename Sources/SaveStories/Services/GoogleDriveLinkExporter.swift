import Foundation

struct GoogleDriveLinkExporter {
    struct ExportRecord: Hashable {
        let id: String
        let header: String
        let filePath: String
    }

    struct ExportOutcome: Hashable {
        let record: ExportRecord
        let link: String?
        let errorMessage: String?
    }

    enum ExporterError: LocalizedError {
        case scriptNotFound
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .scriptNotFound:
                "Не удалось найти встроенный AppleScript для Google Drive automation."
            case .launchFailed(let message):
                message
            }
        }
    }

    func exportLinks(for records: [ExportRecord]) async -> [ExportOutcome] {
        await Task.detached(priority: .userInitiated) {
            records.map { record in
                do {
                    let link = try exportLink(for: record.filePath)
                    return ExportOutcome(record: record, link: link, errorMessage: nil)
                } catch {
                    return ExportOutcome(record: record, link: nil, errorMessage: error.localizedDescription)
                }
            }
        }.value
    }

    private func exportLink(for filePath: String) throws -> String {
        if let driveLink = try googleDriveMetadataLink(for: filePath) {
            return driveLink
        }
        return try runAppleScript(for: filePath)
    }

    private func runAppleScript(for filePath: String) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let sentinel = "SaveMeClipboardSentinel-\(UUID().uuidString)"

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let appleScriptURL = try scriptURL()
        process.arguments = [
            appleScriptURL.path,
            filePath,
            sentinel,
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ExporterError.launchFailed("Не удалось запустить osascript: \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderrText.isEmpty ? stdoutText : stderrText
            throw ExporterError.launchFailed(message.isEmpty ? "AppleScript завершился с ошибкой." : message)
        }

        guard !stdoutText.isEmpty else {
            throw ExporterError.launchFailed("Google Drive automation не вернула ссылку.")
        }

        return stdoutText
    }

    private func googleDriveMetadataLink(for filePath: String) throws -> String? {
        let path = filePath as NSString
        let names = try listExtendedAttributes(atPath: path)
        guard let itemKey = names.first(where: { $0.hasPrefix("com.google.drivefs.item-id") }) else {
            return nil
        }
        guard let itemID = try extendedAttribute(named: itemKey, atPath: path)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !itemID.isEmpty
        else {
            return nil
        }

        return "https://drive.google.com/open?id=\(itemID)"
    }

    private func listExtendedAttributes(atPath path: NSString) throws -> [String] {
        let size = listxattr(path.fileSystemRepresentation, nil, 0, 0)
        guard size >= 0 else {
            throw ExporterError.launchFailed("Не удалось прочитать xattr у файла \(path.lastPathComponent).")
        }
        guard size > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: size)
        let result = listxattr(path.fileSystemRepresentation, &buffer, buffer.count, 0)
        guard result >= 0 else {
            throw ExporterError.launchFailed("Не удалось прочитать список xattr у файла \(path.lastPathComponent).")
        }

        return buffer
            .split(separator: 0)
            .compactMap { String(cString: Array($0) + [0]) }
    }

    private func extendedAttribute(named name: String, atPath path: NSString) throws -> String? {
        let size = getxattr(path.fileSystemRepresentation, name, nil, 0, 0, 0)
        guard size >= 0 else { return nil }
        guard size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        let result = getxattr(path.fileSystemRepresentation, name, &buffer, buffer.count, 0, 0)
        guard result >= 0 else {
            throw ExporterError.launchFailed("Не удалось прочитать xattr \(name) у файла \(path.lastPathComponent).")
        }

        return String(data: Data(buffer), encoding: .utf8)
    }

    private func scriptURL() throws -> URL {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent(AppPaths.resourceBundleName, isDirectory: true)
                .appendingPathComponent("google_drive_copy_link.applescript", isDirectory: false),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(AppPaths.resourceBundleName, isDirectory: true)
                .appendingPathComponent("google_drive_copy_link.applescript", isDirectory: false),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("SaveStories", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("google_drive_copy_link.applescript", isDirectory: false),
        ]

        guard let located = candidates
            .compactMap({ $0 })
            .first(where: { fileManager.fileExists(atPath: $0.path) })
        else {
            throw ExporterError.scriptNotFound
        }

        return located
    }
}
