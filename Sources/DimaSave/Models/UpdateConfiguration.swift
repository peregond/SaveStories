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
        guard let url = Bundle.module.url(forResource: "update_config", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        return try? JSONDecoder().decode(UpdateConfiguration.self, from: data)
    }
}
