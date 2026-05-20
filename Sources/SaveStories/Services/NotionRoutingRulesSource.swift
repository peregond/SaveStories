import Foundation

struct NotionRoutingRulesSource {
    static let defaultPageURL = URL(string: "https://narrow-park-cda.notion.site/366f65c3de6780e8bb03f4bdda65f5f8")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRules(from pageURL: URL = Self.defaultPageURL) async throws -> String {
        let pageID = try Self.pageID(from: pageURL)
        let endpoint = try Self.apiEndpoint(for: pageURL)
        var cursor: [String: Any] = ["stack": []]
        var chunkNumber = 0
        var rules: [String] = []
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
            request.setValue("SaveMe/NotionRoutingRulesSource", forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw NotionRoutingRulesSourceError.httpStatus(httpResponse.statusCode)
            }

            for rule in try Self.parseRules(from: data).split(whereSeparator: \.isNewline).map(String.init)
                where seen.insert(rule.lowercased()).inserted {
                rules.append(rule)
            }

            guard let nextCursor = try Self.nextCursor(from: data),
                  let stack = nextCursor["stack"] as? [Any],
                  !stack.isEmpty else {
                break
            }

            cursor = nextCursor
            chunkNumber += 1
        }

        return rules.joined(separator: "\n")
    }

    static func parseRules(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let recordMap = root["recordMap"] as? [String: Any],
              let blocks = recordMap["block"] as? [String: Any] else {
            return ""
        }

        var texts: [String] = []
        for block in blocks.values {
            guard let blockContainer = block as? [String: Any],
                  let valueContainer = blockContainer["value"] as? [String: Any],
                  let value = valueContainer["value"] as? [String: Any],
                  let properties = value["properties"] as? [String: Any],
                  let title = properties["title"] else {
                continue
            }

            texts.append(notionRichText(title))
        }

        return normalizeRules(texts.joined(separator: "\n"))
    }

    static func normalizeRules(_ text: String) -> String {
        var rules: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  !line.localizedCaseInsensitiveContains("Правила для сортировки"),
                  let separator = line.firstIndex(of: "=") else {
                continue
            }

            let left = String(line[..<separator])
            let target = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { continue }

            for username in normalizedUsernames(from: left) {
                rules.append("\(username) = \(target)")
            }
        }

        return rules.joined(separator: "\n")
    }

    private static func normalizedUsernames(from value: String) -> [String] {
        value
            .split(separator: ":")
            .compactMap { rawPart in
                let part = String(rawPart)
                    .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
                let cleaned = part
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "@*/\\.,;:!?[]{}<>\"'`"))
                return cleaned.isEmpty ? nil : cleaned
            }
    }

    private static func notionRichText(_ value: Any) -> String {
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
        guard let regex = try? NSRegularExpression(pattern: #"[0-9a-fA-F]{32}"#),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
              let range = Range(match.range, in: source) else {
            throw NotionRoutingRulesSourceError.invalidPageURL
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
            throw NotionRoutingRulesSourceError.invalidPageURL
        }
        return endpoint
    }

    private static func nextCursor(from data: Data) throws -> [String: Any]? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { return nil }
        return root["cursor"] as? [String: Any]
    }
}

enum NotionRoutingRulesSourceError: LocalizedError {
    case invalidPageURL
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPageURL:
            "Некорректная ссылка на Notion-страницу с правилами."
        case let .httpStatus(status):
            "Notion вернул HTTP \(status)."
        }
    }
}
