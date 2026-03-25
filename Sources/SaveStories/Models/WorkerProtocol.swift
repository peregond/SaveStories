import Foundation

struct WorkerRequest: Codable {
    let command: String
    let url: String?
    let urls: [String]?
    let outputDirectory: String?
    let headless: Bool?
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

struct WorkerResponse: Codable {
    let ok: Bool
    let status: String
    let message: String
    let data: [String: String]
    let items: [WorkerItem]
    let logs: [String]
}

extension WorkerResponse {
    static func processFailure(message: String) -> WorkerResponse {
        WorkerResponse(
            ok: false,
            status: "process_error",
            message: message,
            data: [:],
            items: [],
            logs: []
        )
    }

    static func cancelled(message: String) -> WorkerResponse {
        WorkerResponse(
            ok: false,
            status: "cancelled",
            message: message,
            data: [:],
            items: [],
            logs: []
        )
    }
}
