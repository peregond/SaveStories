import Foundation

struct UpdateConfiguration: Decodable {
    let repository: String
    let macosFeedURL: String
    let windowsLatestReleaseAPI: String
    let publicEDKey: String

    var macOSFeed: URL? {
        URL(string: macosFeedURL)
    }

    var windowsLatestRelease: URL? {
        URL(string: windowsLatestReleaseAPI)
    }

    var hasPublicEDKey: Bool {
        !publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load() -> UpdateConfiguration? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("DimaSave_DimaSave.bundle", isDirectory: true)
                .appendingPathComponent("update_config.json", isDirectory: false),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("DimaSave_DimaSave.bundle", isDirectory: true)
                .appendingPathComponent("update_config.json", isDirectory: false),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("DimaSave", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("update_config.json", isDirectory: false),
        ]

        guard let url = candidates
            .compactMap({ $0 })
            .first(where: { fileManager.fileExists(atPath: $0.path) }),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        return try? JSONDecoder().decode(UpdateConfiguration.self, from: data)
    }
}
