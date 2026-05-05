import Foundation

struct WorkerRequest: Codable {
    let command: String
    let url: String?
    let urls: [String]?
    let outputDirectory: String?
    let headless: Bool?
    let mediaFilter: String?
}

struct WorkerItem: Codable, Identifiable, Hashable {
    let id: String
    let sourceURL: String
    let pageURL: String
    let localPath: String
    let metadataPath: String
    let mediaType: String
    let createdAt: String
}

struct WorkerCounts: Codable, Hashable {
    let found: Int
    let saved: Int
    let processed: Int
    let failed: Int
}

struct WorkerBatchResult: Codable, Hashable {
    let url: String
    let status: String
    let message: String
    let foundCount: Int
    let savedCount: Int
}

struct WorkerRuntime: Codable, Hashable {
    let kind: String
    let executable: String
    let browserProfile: String
    let playwrightBrowsers: String
    let manifests: String
}

struct WorkerResponse: Codable {
    let ok: Bool
    let status: String
    let message: String
    let protocolVersion: Int?
    let data: [String: String]
    let counts: WorkerCounts?
    let batchResults: [WorkerBatchResult]?
    let runtime: WorkerRuntime?
    let diagnostics: [String: String]?
    let items: [WorkerItem]
    let logs: [String]

    init(
        ok: Bool,
        status: String,
        message: String,
        protocolVersion: Int? = nil,
        data: [String: String],
        counts: WorkerCounts? = nil,
        batchResults: [WorkerBatchResult]? = nil,
        runtime: WorkerRuntime? = nil,
        diagnostics: [String: String]? = nil,
        items: [WorkerItem],
        logs: [String]
    ) {
        self.ok = ok
        self.status = status
        self.message = message
        self.protocolVersion = protocolVersion
        self.data = data
        self.counts = counts
        self.batchResults = batchResults
        self.runtime = runtime
        self.diagnostics = diagnostics
        self.items = items
        self.logs = logs
    }
}

extension WorkerResponse {
    static func processFailure(message: String) -> WorkerResponse {
        WorkerResponse(
            ok: false,
            status: "process_error",
            message: message,
            protocolVersion: 2,
            data: [:],
            counts: nil,
            batchResults: nil,
            runtime: nil,
            diagnostics: [:],
            items: [],
            logs: []
        )
    }

    static func cancelled(message: String) -> WorkerResponse {
        WorkerResponse(
            ok: false,
            status: "cancelled",
            message: message,
            protocolVersion: 2,
            data: [:],
            counts: nil,
            batchResults: nil,
            runtime: nil,
            diagnostics: [:],
            items: [],
            logs: []
        )
    }
}
