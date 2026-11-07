import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// Состояние раздела «Уникализатор»: файлы, настройки, ход обработки. Обработку выполняет общий воркер (unik_* команды).
@MainActor
final class UnikalizatorModel: ObservableObject {
    enum FFmpegPhase: Equatable {
        case unknown
        case missing
        case ready(version: String)
        case installing
        case failed(String)
    }

    private static let optionsKey = "SaveStories.unikalizator.options"
    private static let outputDirectoryKey = "SaveStories.unikalizator.outputDirectory"
    private static let presetsKey = "SaveStories.unikalizator.presets"

    @Published private(set) var catalog: UnikCatalog?
    @Published private(set) var ffmpeg: FFmpegPhase = .unknown
    @Published private(set) var installPercent = 0
    @Published private(set) var installMessage = ""
    @Published private(set) var presets: [UnikPreset] = []
    @Published private(set) var files: [UnikFile] = []
    @Published private(set) var jobs: [UnikJob] = []
    @Published private(set) var summary = ""
    @Published private(set) var isRunning = false
    @Published var notice: String?
    @Published var options = UnikOptions() {
        didSet {
            guard !isPreview, oldValue != options else { return }
            if let data = try? JSONEncoder().encode(options) {
                UserDefaults.standard.set(data, forKey: Self.optionsKey)
            }
        }
    }
    @Published var outputDirectory: URL {
        didSet {
            guard !isPreview else { return }
            UserDefaults.standard.set(outputDirectory.path, forKey: Self.outputDirectoryKey)
        }
    }

    private let worker: WorkerClient
    private let isPreview: Bool
    private var sleepActivity: NSObjectProtocol?
    private var previewSamplesLoaded = false

    init(worker: WorkerClient = WorkerClient(), isPreview: Bool = false) {
        self.worker = worker
        self.isPreview = isPreview
        outputDirectory = AppPaths.defaultDownloads.appendingPathComponent("Уникализатор", isDirectory: true)
        guard !isPreview else { return }
        if let path = UserDefaults.standard.string(forKey: Self.outputDirectoryKey), !path.isEmpty {
            outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }
        presets = UnikalizatorLogic.decodePresets(UserDefaults.standard.data(forKey: Self.presetsKey))
        if let data = UserDefaults.standard.data(forKey: Self.optionsKey),
           let saved = try? JSONDecoder().decode(UnikOptions.self, from: data)
        {
            options = saved
        }
    }

    var plannedOutputs: Int { UnikalizatorLogic.plannedOutputs(fileCount: files.count, options: options) }
    var problems: [String] { UnikalizatorLogic.problems(options: options, fileCount: files.count) }
    var isFFmpegReady: Bool {
        if case .ready = ffmpeg { return true }
        return false
    }
    var isInstalling: Bool { ffmpeg == .installing }
    var doneCount: Int { jobs.filter { $0.status == .done }.count }
    var overallPercent: Int {
        guard !jobs.isEmpty else { return 0 }
        let total = jobs.reduce(0) { $0 + ($1.status == .done || $1.status == .error ? 100 : $1.percent) }
        return total / jobs.count
    }

    /// Только для снимков экрана в режиме предпросмотра: вымышленные файлы и ход обработки.
    func loadPreviewSamples() {
        guard isPreview else { return }
        previewSamplesLoaded = true
        ffmpeg = .ready(version: "7.1")
        files = [
            UnikFile(path: "/Users/preview/Movies/story-01.mp4", info: "1080×1920 · 0:12"),
            UnikFile(path: "/Users/preview/Movies/story-02.mp4", info: "720×1280 · 0:08"),
            UnikFile(path: "/Users/preview/Pictures/banner.png", info: "1500×1500"),
        ]
        options.variations.count = 2
        options.ageMark = UnikOptions.AgeMark(enabled: true, geoId: "de-germany", position: "bottom")
        jobs = [
            UnikJob(index: 1, label: "story-01 · v1", percent: 100, status: .done, outputPath: "/Users/preview/Downloads/SaveMe/Уникализатор/DE_meta_9x16_v1.mp4"),
            UnikJob(index: 2, label: "story-01 · v2", percent: 100, status: .done, outputPath: "/Users/preview/Downloads/SaveMe/Уникализатор/DE_meta_9x16_v2.mp4"),
            UnikJob(index: 3, label: "story-02 · v1", percent: 62, status: .running),
            UnikJob(index: 4, label: "story-02 · v2", status: .queued),
            UnikJob(index: 5, label: "banner · v1", status: .queued),
            UnikJob(index: 6, label: "banner · v2", status: .queued),
        ]
        summary = "Готово 2 из 6"
        presets = [UnikPreset(name: "Reels DE 18+", options: options), UnikPreset(name: "Квадрат без плашки", options: UnikOptions())]
    }

    // MARK: FFmpeg

    func refresh() async {
        let response = await worker.run(WorkerRequest(command: "unik_status", url: nil, urls: nil, outputDirectory: nil, headless: nil, mediaFilter: nil))
        guard response.ok else {
            ffmpeg = .failed(response.message)
            return
        }
        if let json = response.data["catalog"], let data = json.data(using: .utf8) {
            catalog = try? JSONDecoder().decode(UnikCatalog.self, from: data)
        }
        guard !isInstalling, !previewSamplesLoaded else { return }
        ffmpeg = response.data["ffmpegInstalled"] == "true" ? .ready(version: response.data["ffmpegVersion"] ?? "") : .missing
    }

    func installFFmpeg() async {
        ffmpeg = .installing
        installPercent = 0
        installMessage = "Готовлюсь к установке…"
        let response = await worker.run(
            WorkerRequest(command: "unik_install_ffmpeg", url: nil, urls: nil, outputDirectory: nil, headless: nil, mediaFilter: nil),
            onProgress: { [weak self] line in
                Task { @MainActor in self?.handle(line: line) }
            }
        )
        if response.ok {
            ffmpeg = .ready(version: response.data["ffmpegVersion"] ?? "")
            notice = response.message
        } else {
            ffmpeg = .failed(response.message)
        }
    }

    func setVariationCount(_ count: Int) {
        var variations = options.variations
        let first = variations.styleIds.first ?? "clean"
        variations.count = count
        variations.styleIds = (0 ..< count).map { $0 < variations.styleIds.count ? variations.styleIds[$0] : first }
        options.variations = variations
    }

    func setStyle(slot: Int, id: String) {
        guard slot >= 0, slot < options.variations.styleIds.count else { return }
        options.variations.styleIds[slot] = id
    }

    func applyFormatPreset(_ id: String) {
        guard let preset = catalog?.formatPresets.first(where: { $0.id == id }) else {
            options.formatPresetId = "custom"
            return
        }
        options.formatPresetId = id
        options.resize = preset.resize
        options.fps = preset.fps
        options.bitrate = preset.bitrate
    }

    // MARK: Файлы

    func addFiles(_ urls: [URL]) {
        let paths = urls.map(\.path)
        let media = paths.filter(UnikalizatorLogic.isMedia)
        let rejected = paths.count - media.count
        if rejected > 0 { notice = "Пропущено файлов неподдерживаемого типа: \(rejected)." }
        var fresh: [String] = []
        for path in media where !files.contains(where: { $0.path.caseInsensitiveCompare(path) == .orderedSame }) && !fresh.contains(path) {
            fresh.append(path)
        }
        guard !fresh.isEmpty else { return }
        files.append(contentsOf: fresh.map { UnikFile(path: $0, info: "") })
        if isFFmpegReady, !isRunning {
            Task { await inspect(fresh) }
        }
    }

    func removeFile(_ file: UnikFile) { files.removeAll { $0.path == file.path } }
    func clearFiles() { files.removeAll() }

    // MARK: Свои пресеты

    func savePreset(named name: String) { setPresets(UnikalizatorLogic.upsertingPreset(presets, name: name, options: options)) }
    func deletePreset(named name: String) { setPresets(UnikalizatorLogic.removingPreset(presets, name: name)) }

    func applyPreset(named name: String) {
        if let preset = presets.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
            options = preset.options
        }
    }

    private func setPresets(_ list: [UnikPreset]) {
        guard list != presets else { return }
        presets = list
        guard !isPreview, let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: Self.presetsKey)
    }

    private func inspect(_ paths: [String]) async {
        var request = WorkerRequest(command: "unik_inspect", url: nil, urls: nil, outputDirectory: nil, headless: nil, mediaFilter: nil)
        request.files = paths
        let response = await worker.run(request)
        guard let json = response.data["inspections"], let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([UnikInspection].self, from: data) else { return }
        for item in list {
            if let index = files.firstIndex(where: { $0.path == item.filePath }) {
                files[index].info = UnikalizatorLogic.describe(item)
            }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Исходные видео и картинки"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = UnikalizatorLogic.mediaExtensions.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    /// Выбор одного файла (заставка, видео-слой, звук) или набора файлов.
    func chooseFiles(title: String, extensions: [String], multiple: Bool) -> [String] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.urls.map(\.path) : []
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Папка для результатов"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = outputDirectory
        if panel.runModal() == .OK, let url = panel.url { outputDirectory = url }
    }

    func revealOutput() {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(outputDirectory)
    }

    // MARK: Обработка

    func run() async {
        guard !isRunning, isFFmpegReady, problems.isEmpty else { return }
        isRunning = true
        notice = nil
        jobs = []
        summary = "Запускаю обработку…"
        sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "Обработка видео в «Уникализаторе»")
        defer {
            isRunning = false
            if let activity = sleepActivity { ProcessInfo.processInfo.endActivity(activity) }
            sleepActivity = nil
        }
        var request = WorkerRequest(command: "unik_process", url: nil, urls: nil, outputDirectory: outputDirectory.path, headless: nil, mediaFilter: nil)
        request.sources = files.map(\.path)
        request.options = options
        let response = await worker.run(request, onProgress: { [weak self] line in
            Task { @MainActor in self?.handle(line: line) }
        })
        if let json = response.data["results"], let data = json.data(using: .utf8),
           let results = try? JSONDecoder().decode([UnikResult].self, from: data)
        {
            for result in results where result.index >= 0 && result.index < jobs.count {
                jobs[result.index].status = result.status == "completed" ? .done : .error
                jobs[result.index].outputPath = result.outputPath
                jobs[result.index].message = String(result.message.split(separator: "\n").first ?? "")
                if result.status == "completed" { jobs[result.index].percent = 100 }
            }
        }
        summary = response.message
        if response.status == "cancelled" {
            notice = "Обработка остановлена."
        } else if !response.ok {
            notice = response.message
        }
    }

    func stop() {
        worker.stopCurrentProcess()
    }

    private func handle(line raw: String) {
        guard let line = UnikalizatorLogic.parseLine(raw) else { return }
        switch line {
        case .ffmpegProgress(let percent):
            if isInstalling { installPercent = percent }
        case .ffmpegMessage(let text):
            if isInstalling { installMessage = text }
        default:
            jobs = UnikalizatorLogic.apply(line, to: jobs)
        }
    }
}
