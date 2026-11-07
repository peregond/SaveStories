import Foundation

// Модели раздела «Уникализатор». Сама обработка (FFmpeg, вариации, имена) выполняется общим воркером
// node_worker/unik_*.mjs; здесь настройки, каталог, разбор строк прогресса и чистая логика (её проверяют тесты).

struct UnikResize: Codable, Hashable, Sendable {
    var width = 1080
    var height = 1920
    var fit = "cover"
    var backgroundStyle = "bars"
    var backgroundColor = "#111111"
}

struct UnikFormatPreset: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let resize: UnikResize
    let fps: Int
    let bitrate: String
}

struct UnikStylePreset: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let hint: String
}

struct UnikBitrateOption: Decodable, Identifiable, Hashable, Sendable {
    let value: String
    let label: String
    let hint: String
    var id: String { value }
}

struct UnikGeo: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct UnikCatalog: Decodable, Sendable {
    let formatPresets: [UnikFormatPreset]
    let stylePresets: [UnikStylePreset]
    let fpsOptions: [Int]
    let variationOptions: [Int]
    let bitrateOptions: [UnikBitrateOption]
    let ageMarkGeos: [UnikGeo]
}

/// Настройки обработки. Имена полей совпадают с тем, что ждёт воркер (unik_batch.mjs: normalizeOptions).
struct UnikOptions: Codable, Hashable, Sendable {
    struct Variations: Codable, Hashable, Sendable {
        var count = 1
        var styleIds: [String] = ["clean"]
        var mode = "all-variations"
    }

    struct Manual: Codable, Hashable, Sendable {
        var enabled = false
        var hueShift = 0.0
        var saturation = 1.0
        var sharpness = 0.0
        var speedOffsetMs = 0.0
    }

    struct AgeMark: Codable, Hashable, Sendable {
        var enabled = false
        var geoId = ""
        var position = "bottom"
    }

    struct Intro: Codable, Hashable, Sendable {
        var enabled = false
        var imagePath = ""
        var durationMs = 500.0
        var random = false
        var library: [String] = []
    }

    struct Overlay: Codable, Hashable, Sendable {
        var enabled = false
        var videoPath = ""
        var opacity = 0.25
        var random = false
        var library: [String] = []
    }

    struct Audio: Codable, Hashable, Sendable {
        var normalize = true
        var replacePath = ""
    }

    struct Metadata: Codable, Hashable, Sendable {
        var mode = "strip"
        var customDate = ""
    }

    struct Naming: Codable, Hashable, Sendable {
        var mode = "structured"
        var geo = ""
        var presetToken = ""
        var versionToken = "v1"
        var randomTail = ""
    }

    var formatPresetId = "meta-story"
    var resize = UnikResize()
    /// 0 — оставить частоту кадров как есть.
    var fps = 30
    var bitrate = "2M"
    var variations = Variations()
    var manual = Manual()
    var ageMark = AgeMark()
    var intro = Intro()
    var overlay = Overlay()
    var audio = Audio()
    var metadata = Metadata()
    var naming = Naming()
}

struct UnikFile: Identifiable, Hashable, Sendable {
    let path: String
    var info: String
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var isImage: Bool { UnikalizatorLogic.isImage(path) }
}

struct UnikJob: Identifiable, Hashable, Sendable {
    enum Status: String, Sendable { case queued, running, done, error }

    let index: Int
    var label = ""
    var percent = 0
    var status: Status = .queued
    var outputPath = ""
    var message = ""
    var id: Int { index }
}

struct UnikResult: Decodable, Sendable {
    let index: Int
    let source: String
    let outputPath: String
    let status: String
    let message: String
}

struct UnikInspection: Decodable, Sendable {
    let ok: Bool
    let filePath: String
    let kind: String?
    let durationSeconds: Double?
    let width: Int?
    let height: Int?
    let hasAudio: Bool?
    let message: String?
}

enum UnikLine: Equatable, Sendable {
    case total(Int)
    case job(index: Int, phase: String, value: String)
    case ffmpegProgress(Int)
    case ffmpegMessage(String)
}

/// Набор настроек под своим именем («Reels DE 18+»).
struct UnikPreset: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var options: UnikOptions
    var id: String { name.lowercased() }
}

enum UnikalizatorLogic {
    static let maxPresets = 50

    static func cleanPresetName(_ name: String) -> String {
        String(name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(60))
    }

    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .caseInsensitive) == .orderedSame
    }

    /// Добавляет набор или заменяет одноимённый (без учёта регистра). Пустое имя — без изменений.
    static func upsertingPreset(_ list: [UnikPreset], name: String, options: UnikOptions) -> [UnikPreset] {
        let clean = cleanPresetName(name)
        guard !clean.isEmpty else { return list }
        let entry = UnikPreset(name: clean, options: options)
        if let index = list.firstIndex(where: { sameName($0.name, clean) }) {
            var copy = list
            copy[index] = entry
            return copy
        }
        return list.count >= maxPresets ? list : list + [entry]
    }

    static func removingPreset(_ list: [UnikPreset], name: String) -> [UnikPreset] {
        list.filter { !sameName($0.name, name) }
    }

    /// Список из сохранённых данных: испорченные записи и повторы имён отбрасываются.
    static func decodePresets(_ data: Data?) -> [UnikPreset] {
        struct Lossy: Decodable {
            let value: UnikPreset?
            init(from decoder: Decoder) throws { value = try? UnikPreset(from: decoder) }
        }
        guard let data, let raw = try? JSONDecoder().decode([Lossy].self, from: data) else { return [] }
        var list: [UnikPreset] = []
        for case let preset? in raw.map(\.value) {
            let name = cleanPresetName(preset.name)
            guard !name.isEmpty, !list.contains(where: { sameName($0.name, name) }) else { continue }
            list.append(UnikPreset(name: name, options: preset.options))
            if list.count >= maxPresets { break }
        }
        return list
    }

    static let videoExtensions = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]
    static let imageExtensions = ["png", "jpg", "jpeg", "webp"]
    static let audioExtensions = ["mp3", "m4a", "aac", "wav", "ogg", "flac"]
    static var mediaExtensions: [String] { videoExtensions + imageExtensions }

    static func fileExtension(_ path: String) -> String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    static func isMedia(_ path: String) -> Bool { mediaExtensions.contains(fileExtension(path)) }
    static func isImage(_ path: String) -> Bool { imageExtensions.contains(fileExtension(path)) }

    /// Сколько файлов получится на выходе (как в воркере).
    static func plannedOutputs(fileCount: Int, options: UnikOptions) -> Int {
        guard fileCount > 0 else { return 0 }
        if options.variations.mode == "preset-per-file", fileCount > 1 { return fileCount }
        return fileCount * options.variations.count
    }

    static func sizeToken(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "custom" }
        let ratio = Double(width) / Double(height)
        if abs(ratio - 9.0 / 16.0) < 0.02 { return "9x16" }
        if abs(ratio - 1) < 0.02 { return "1x1" }
        if abs(ratio - 4.0 / 5.0) < 0.02 { return "4x5" }
        if abs(ratio - 1.91) < 0.03 { return "191x1" }
        if abs(ratio - 16.0 / 9.0) < 0.02 { return "16x9" }
        return "\(width)x\(height)"
    }

    static func slug(_ value: String) -> String {
        String(value.unicodeScalars.filter { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) })
    }

    /// Пример имени результата для подсказки под полями названия.
    static func previewName(options: UnikOptions, firstFile: String, outputs: Int, index: Int = 0) -> String {
        var ext = "mp4"
        if !firstFile.isEmpty, isImage(firstFile) {
            ext = fileExtension(firstFile) == "jpeg" ? "jpg" : fileExtension(firstFile)
        }
        if options.naming.mode == "source-random" {
            let stem = firstFile.isEmpty ? "result" : URL(fileURLWithPath: firstFile).deletingPathExtension().lastPathComponent
            let tail = options.naming.randomTail.isEmpty ? "Asdc56Dg" : slug(options.naming.randomTail)
            return "\(stem)_\(tail).\(ext)"
        }
        let digits = options.naming.versionToken.reversed().prefix(while: { $0.isNumber }).reversed()
        let start = Int(String(digits)) ?? 1
        let version = outputs > 1 ? "v\(max(start, 1) + index)" : options.naming.versionToken
        let parts = [options.naming.geo, options.naming.presetToken, sizeToken(width: options.resize.width, height: options.resize.height), version]
            .map(slug)
            .filter { !$0.isEmpty }
        return "\(parts.isEmpty ? "result" : parts.joined(separator: "_")).\(ext)"
    }

    /// Проверка до запуска: понятные причины, почему кнопка «Создать» недоступна.
    static func problems(options o: UnikOptions, fileCount: Int) -> [String] {
        var result: [String] = []
        if fileCount == 0 { result.append("Добавьте хотя бы один файл.") }
        let width = o.resize.width
        let height = o.resize.height
        if width < 2 || height < 2 || width > 8192 || height > 8192 {
            result.append("Размер кадра — от 2 до 8192 пикселей.")
        } else if width % 2 != 0 || height % 2 != 0 {
            result.append("Ширина и высота должны быть чётными.")
        }
        if o.ageMark.enabled, o.ageMark.geoId.isEmpty { result.append("Выберите страну для плашки 18+.") }
        if o.intro.enabled, !o.intro.random, o.intro.imagePath.isEmpty { result.append("Выберите картинку для заставки.") }
        if o.intro.enabled, o.intro.random, o.intro.library.isEmpty { result.append("В наборе заставок нет файлов.") }
        if o.overlay.enabled, !o.overlay.random, o.overlay.videoPath.isEmpty { result.append("Выберите видео для слоя поверх.") }
        if o.overlay.enabled, o.overlay.random, o.overlay.library.isEmpty { result.append("В наборе видео-слоёв нет файлов.") }
        if o.metadata.mode == "custom-date", !isValidDate(o.metadata.customDate) { result.append("Укажите дату в метаданных.") }
        return result
    }

    static func isValidDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return false }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        return check.year == year && check.month == month && check.day == day
    }

    /// Разбор строки прогресса воркера (unik_*), остальные строки — nil.
    static func parseLine(_ line: String) -> UnikLine? {
        if line.hasPrefix("unik_total="), let total = Int(line.dropFirst("unik_total=".count)) { return .total(total) }
        if line.hasPrefix("unik_ffmpeg_progress="), let percent = Int(line.dropFirst("unik_ffmpeg_progress=".count)) { return .ffmpegProgress(percent) }
        if line.hasPrefix("unik_ffmpeg_message=") { return .ffmpegMessage(String(line.dropFirst("unik_ffmpeg_message=".count))) }
        if line.hasPrefix("unik_job_") {
            let rest = line.dropFirst("unik_job_".count)
            guard let equals = rest.firstIndex(of: "="), let underscore = rest.firstIndex(of: "_"), underscore < equals,
                  let index = Int(rest[rest.startIndex ..< underscore]) else { return nil }
            let phase = String(rest[rest.index(after: underscore) ..< equals])
            guard ["start", "progress", "done", "error"].contains(phase) else { return nil }
            return .job(index: index, phase: phase, value: String(rest[rest.index(after: equals)...]))
        }
        return nil
    }

    static func apply(_ line: UnikLine, to jobs: [UnikJob]) -> [UnikJob] {
        switch line {
        case .total(let total):
            return (0 ..< max(total, 0)).map { UnikJob(index: $0) }
        case .job(let index, let phase, let value):
            guard index >= 0 else { return jobs }
            var next = jobs
            while next.count <= index { next.append(UnikJob(index: next.count)) }
            var job = next[index]
            switch phase {
            case "start": job.status = .running; job.label = value; job.percent = 0
            case "progress": job.percent = Int(value) ?? job.percent
            case "done": job.status = .done; job.percent = 100; job.outputPath = value
            default: job.status = .error; job.message = value
            }
            next[index] = job
            return next
        default:
            return jobs
        }
    }

    static func describe(_ inspection: UnikInspection) -> String {
        guard inspection.ok else { return inspection.message ?? "Файл не удалось прочитать." }
        var parts: [String] = []
        if let width = inspection.width, let height = inspection.height { parts.append("\(width)×\(height)") }
        if inspection.kind == "video" {
            if let seconds = inspection.durationSeconds, seconds > 0 {
                parts.append("\(Int(seconds) / 60):" + String(format: "%02d", Int(seconds.rounded()) % 60))
            }
            parts.append(inspection.hasAudio == true ? "со звуком" : "без звука")
        } else {
            parts.append("картинка")
        }
        return parts.joined(separator: " · ")
    }
}
