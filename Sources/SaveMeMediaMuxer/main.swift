import AVFoundation
import Foundation

enum MediaMuxerError: LocalizedError {
    case usage
    case missingTrack(kind: String, url: URL)
    case cannotCreateCompositionTrack(kind: String)
    case cannotCreateExporter
    case unsupportedOutput
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: SaveMeMediaMuxer <video-only.mp4> <audio-only.mp4> <output.mp4>"
        case let .missingTrack(kind, url):
            return "No \(kind) track in \(url.path)"
        case let .cannotCreateCompositionTrack(kind):
            return "Cannot create \(kind) composition track"
        case .cannotCreateExporter:
            return "Cannot create passthrough exporter"
        case .unsupportedOutput:
            return "The input tracks cannot be exported as MP4 without re-encoding"
        case let .exportFailed(message):
            return "Export failed: \(message)"
        }
    }
}

@main
struct SaveMeMediaMuxer {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 3 else {
                throw MediaMuxerError.usage
            }

            let videoURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
            let audioURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            let outputURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL

            guard !FileManager.default.fileExists(atPath: outputURL.path) else {
                throw MediaMuxerError.exportFailed("output already exists: \(outputURL.path)")
            }

            try await mux(videoURL: videoURL, audioURL: audioURL, outputURL: outputURL)
            print(outputURL.path)
        } catch {
            fputs("SaveMeMediaMuxer: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw MediaMuxerError.missingTrack(kind: "video", url: videoURL)
        }
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw MediaMuxerError.missingTrack(kind: "audio", url: audioURL)
        }

        let videoTimeRange = try await videoTrack.load(.timeRange)
        let audioTimeRange = try await audioTrack.load(.timeRange)
        guard videoTimeRange.duration.isNumeric, videoTimeRange.duration > .zero else {
            throw MediaMuxerError.exportFailed("video duration is invalid")
        }
        guard audioTimeRange.duration.isNumeric, audioTimeRange.duration > .zero else {
            throw MediaMuxerError.exportFailed("audio duration is invalid")
        }

        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MediaMuxerError.cannotCreateCompositionTrack(kind: "video")
        }
        guard let compositionAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MediaMuxerError.cannotCreateCompositionTrack(kind: "audio")
        }

        try compositionVideo.insertTimeRange(videoTimeRange, of: videoTrack, at: .zero)
        compositionVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        let audioDuration = CMTimeMinimum(audioTimeRange.duration, videoTimeRange.duration)
        let trimmedAudioRange = CMTimeRange(start: audioTimeRange.start, duration: audioDuration)
        try compositionAudio.insertTimeRange(trimmedAudioRange, of: audioTrack, at: .zero)

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw MediaMuxerError.cannotCreateExporter
        }
        guard exporter.supportedFileTypes.contains(.mp4) else {
            throw MediaMuxerError.unsupportedOutput
        }

        exporter.shouldOptimizeForNetworkUse = true
        if #available(macOS 15.0, *) {
            try await exporter.export(to: outputURL, as: .mp4)
        } else {
            try await exportLegacy(exporter, outputURL: outputURL)
        }
    }

    @available(macOS, deprecated: 15.0)
    private static func exportLegacy(
        _ exporter: AVAssetExportSession,
        outputURL: URL
    ) async throws {
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        switch exporter.status {
        case .completed:
            return
        case .cancelled:
            throw CancellationError()
        default:
            throw MediaMuxerError.exportFailed(
                exporter.error?.localizedDescription ?? "status \(exporter.status.rawValue)"
            )
        }
    }
}
