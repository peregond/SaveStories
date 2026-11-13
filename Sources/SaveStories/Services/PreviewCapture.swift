import AppKit
import Foundation

/// Служебные аргументы режима предпросмотра дизайна (`--design-preview`), нужные для снимков экрана в CI:
/// `--preview-section=<main|reels|unikalizator|sorting|settings>`, `--preview-appearance=<light|dark>`,
/// `--preview-screenshot=<путь к PNG>` (сохранить снимок окна и закрыть приложение),
/// `--preview-window-id-file=<путь>` (записать номер окна и держать приложение открытым ~60 с: снимок делает внешний `screencapture -l`,
/// он рисует и боковую панель, и полупрозрачные материалы, которые собственный снимок окна не передаёт).
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
    static var windowIDFilePath: String? { argument("preview-window-id-file") }
    static var wantsSamples: Bool { ProcessInfo.processInfo.arguments.contains("--preview-samples") }
    /// `--preview-size=1500x1100`: размер окна на момент снимка (экран раннера маленький, а картинка рисуется и за его пределами).
    static var size: CGSize? {
        guard let raw = argument("preview-size") else { return nil }
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
    }

    @MainActor
    static func publishWindowIDAndWait(to path: String) async {
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        defer { NSApp.terminate(nil) }
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
            FileHandle.standardError.write(Data("preview-window-id-file: нет видимого окна\n".utf8))
            return
        }
        if let size {
            var frame = window.frame
            frame.origin.y += frame.height - size.height
            frame.size = size
            window.setFrame(frame, display: true)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        try? "\(window.windowNumber)".write(toFile: path, atomically: true, encoding: .utf8)
        print("preview-window-id-file: \(path) window=\(window.windowNumber) frame=\(window.frame)")
        try? await Task.sleep(nanoseconds: 60_000_000_000)
    }

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
        if let size {
            var frame = window.frame
            frame.origin.y += frame.height - size.height
            frame.size = size
            window.setFrame(frame, display: true)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
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
