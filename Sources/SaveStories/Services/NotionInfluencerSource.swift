import Foundation

struct NotionInfluencerSource {
    static let defaultPageURL = URL(string: "https://narrow-park-cda.notion.site/334f65c3de678035bfecd4b7bf2a7fa7")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchProfiles(from pageURL: URL = Self.defaultPageURL) async throws -> [String] {
        let pageID = try Self.pageID(from: pageURL)
        let endpoint = try Self.apiEndpoint(for: pageURL)
        var cursor: [String: Any] = ["stack": []]
        var chunkNumber = 0
        var allProfiles: [String] = []
        var seen = Set<String>()

        while chunkNumber < 10 {
            let payload: [String: Any] = [
                "pageId": pageID,
                "limit": 100,
                "cursor": cursor,
                "chunkNumber": chunkNumber,
                "verticalColumns": false,
            ]

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("SaveMe/NotionInfluencerSource", forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw NotionInfluencerSourceError.httpStatus(httpResponse.statusCode)
            }

            let parsed = try Self.parseProfiles(from: data)
            for profile in parsed where seen.insert(profile.lowercased()).inserted {
                allProfiles.append(profile)
            }

            guard let nextCursor = try Self.nextCursor(from: data),
                  let stack = nextCursor["stack"] as? [Any],
                  !stack.isEmpty else {
                break
            }

            cursor = nextCursor
            chunkNumber += 1
        }

        return allProfiles
    }

    static func parseProfiles(from data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let recordMap = root["recordMap"] as? [String: Any],
              let blocks = recordMap["block"] as? [String: Any] else {
            return []
        }

        let blockValues: [String: [String: Any]] = blocks.reduce(into: [:]) { result, element in
            guard let blockContainer = element.value as? [String: Any],
                  let valueContainer = blockContainer["value"] as? [String: Any],
                  let value = valueContainer["value"] as? [String: Any] else {
                return
            }
            result[element.key] = value
        }

        var profiles: [String] = []
        var seen = Set<String>()
        var visited = Set<String>()

        func collectProfiles(from value: [String: Any]) {
            guard let properties = value["properties"] as? [String: Any],
                  let title = properties["title"] else {
                return
            }

            for profile in extractProfiles(from: notionRichText(title)) where seen.insert(profile.lowercased()).inserted {
                profiles.append(profile)
            }
        }

        func visit(_ id: String, includeSelf: Bool = true) {
            guard visited.insert(id).inserted,
                  let value = blockValues[id] else {
                return
            }

            if includeSelf {
                collectProfiles(from: value)
            }

            for childID in value["content"] as? [String] ?? [] {
                visit(childID)
            }
        }

        let pageIDs = blockValues
            .filter { $0.value["type"] as? String == "page" }
            .map(\.key)

        for pageID in pageIDs {
            visit(pageID, includeSelf: false)
        }

        for id in blockValues.keys {
            visit(id)
        }

        return profiles
    }

    static func extractProfiles(from text: String) -> [String] {
        var profiles: [String] = []
        var seen = Set<String>()

        func appendUsername(_ username: String) {
            guard let normalized = normalizeInstagramUsername(username),
                  seen.insert(normalized.lowercased()).inserted else {
                return
            }
            profiles.append("https://www.instagram.com/\(normalized)/")
        }

        for match in regexMatches(#"https?://(?:www\.)?instagram\.com/([A-Za-z0-9._]{1,30})(?:/|\b)"#, in: text) {
            appendUsername(match)
        }

        for match in regexMatches(#"(?<![A-Za-z0-9._])@([A-Za-z0-9._]{1,30})(?![A-Za-z0-9._])"#, in: text) {
            appendUsername(match)
        }

        if profiles.isEmpty {
            for token in text.split(whereSeparator: { character in
                character.isWhitespace || character == "," || character == ";"
            }) {
                appendUsername(String(token))
            }
        }

        return profiles
    }

    static func notionRichText(_ value: Any) -> String {
        guard let fragments = value as? [Any] else {
            return value as? String ?? ""
        }

        return fragments.compactMap { fragment in
            if let tuple = fragment as? [Any],
               let text = tuple.first as? String {
                return text
            }
            return fragment as? String
        }.joined()
    }

    private static func pageID(from url: URL) throws -> String {
        let source = url.absoluteString
        let pattern = #"[0-9a-fA-F]{32}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
              let range = Range(match.range, in: source) else {
            throw NotionInfluencerSourceError.invalidPageURL
        }

        let compact = String(source[range]).lowercased()
        return [
            compact.prefix(8),
            compact.dropFirst(8).prefix(4),
            compact.dropFirst(12).prefix(4),
            compact.dropFirst(16).prefix(4),
            compact.dropFirst(20),
        ].map(String.init).joined(separator: "-")
    }

    private static func apiEndpoint(for pageURL: URL) throws -> URL {
        guard let scheme = pageURL.scheme,
              let host = pageURL.host,
              let endpoint = URL(string: "\(scheme)://\(host)/api/v3/loadCachedPageChunk") else {
            throw NotionInfluencerSourceError.invalidPageURL
        }
        return endpoint
    }

    private static func nextCursor(from data: Data) throws -> [String: Any]? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { return nil }
        return root["cursor"] as? [String: Any]
    }

    private static func normalizeInstagramUsername(_ raw: String) -> String? {
        let username = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@*/\\.,;:!?()[]{}<>\"'`"))

        guard username.range(of: #"^[A-Za-z0-9._]{1,30}$"#, options: .regularExpression) != nil else {
            return nil
        }

        let blocked = ["instagram", "profile", "profiles", "username", "user", "name", "link", "links"]
        guard !blocked.contains(username.lowercased()) else {
            return nil
        }

        return username
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }
}

enum NotionInfluencerSourceError: LocalizedError {
    case invalidPageURL
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPageURL:
            "Некорректная ссылка на Notion-страницу."
        case let .httpStatus(status):
            "Notion вернул HTTP \(status)."
        }
    }
}
