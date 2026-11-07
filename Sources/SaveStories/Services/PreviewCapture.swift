import AppKit
import Foundation

/// Служебные аргументы режима предпросмотра дизайна (`--design-preview`), нужные для снимков экрана в CI:
/// `--preview-section=<main|reels|unikalizator|sorting|settings>`, `--preview-appearance=<light|dark>`,
/// `--preview-screenshot=<путь к PNG>` (сохранить снимок окна и закрыть приложение).
/// Вне режима предпросмотра ничего из этого не действует.
enum PreviewCapture {
    private static func argument(_ name: String) -> String? {
        let prefix = "--\(name)="
        return ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    static var section: String? { argument("preview-section") }
    static var appearance: String? { argument("preview-appearance") }
    static var screenshotPath: String? { argument("preview-screenshot") }

    @MainActor
    static func captureAndQuit(to path: String) async {
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        defer { NSApp.terminate(nil) }
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let content = window.contentView
        else {
            FileHandle.standardError.write(Data("preview-screenshot: нет видимого окна\n".utf8))
            return
        }
        let target = content.superview ?? content
        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return }
        target.cacheDisplay(in: target.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("preview-screenshot: \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
        } catch {
            FileHandle.standardError.write(Data("preview-screenshot: \(error)\n".utf8))
        }
    }
}
