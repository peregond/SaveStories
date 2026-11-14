import XCTest
@testable import SaveMe

final class UnikalizatorTests: XCTestCase {
    func testPlannedOutputsFollowVariationsAndMode() {
        var options = UnikOptions()
        XCTAssertEqual(UnikalizatorLogic.plannedOutputs(fileCount: 0, options: options), 0)
        options.variations.count = 2
        XCTAssertEqual(UnikalizatorLogic.plannedOutputs(fileCount: 3, options: options), 6)
        options.variations.mode = "preset-per-file"
        XCTAssertEqual(UnikalizatorLogic.plannedOutputs(fileCount: 3, options: options), 3)
        XCTAssertEqual(UnikalizatorLogic.plannedOutputs(fileCount: 1, options: options), 2)
    }

    func testPreviewNameMatchesWorkerScheme() {
        var options = UnikOptions()
        options.naming.geo = "au"
        options.naming.presetToken = "insta gram"
        options.naming.versionToken = "v3"
        XCTAssertEqual(UnikalizatorLogic.previewName(options: options, firstFile: "/x/a.mp4", outputs: 1), "au_instagram_9x16_v3.mp4")
        XCTAssertEqual(UnikalizatorLogic.previewName(options: options, firstFile: "/x/a.mp4", outputs: 3, index: 2), "au_instagram_9x16_v5.mp4")
        XCTAssertEqual(UnikalizatorLogic.previewName(options: options, firstFile: "/x/pic.jpeg", outputs: 1), "au_instagram_9x16_v3.jpg")
        options.naming.mode = "source-random"
        options.naming.randomTail = "Qwe 12"
        XCTAssertEqual(UnikalizatorLogic.previewName(options: options, firstFile: "/x/clip.mov", outputs: 1), "clip_Qwe12.mp4")
        XCTAssertEqual(UnikalizatorLogic.sizeToken(width: 1200, height: 628), "191x1")
        XCTAssertEqual(UnikalizatorLogic.sizeToken(width: 800, height: 700), "800x700")
    }

    func testProblemsNameTheReasons() {
        var options = UnikOptions()
        XCTAssertEqual(UnikalizatorLogic.problems(options: options, fileCount: 0), ["Добавьте хотя бы один файл."])
        XCTAssertTrue(UnikalizatorLogic.problems(options: options, fileCount: 2).isEmpty)
        options.resize.width = 1081
        options.ageMark.enabled = true
        options.intro.enabled = true
        options.overlay.enabled = true
        options.overlay.random = true
        options.metadata.mode = "custom-date"
        let text = UnikalizatorLogic.problems(options: options, fileCount: 1).joined(separator: "|")
        for part in ["чётными", "страну", "заставки", "видео-слоёв", "дату"] {
            XCTAssertTrue(text.contains(part), "нет «\(part)» в: \(text)")
        }
        XCTAssertTrue(UnikalizatorLogic.isValidDate("2026-11-06"))
        XCTAssertFalse(UnikalizatorLogic.isValidDate("2026-02-31"))
        XCTAssertFalse(UnikalizatorLogic.isValidDate("06.11.2026"))
    }

    func testProgressLinesAreParsedAndApplied() {
        XCTAssertEqual(UnikalizatorLogic.parseLine("unik_total=4"), .total(4))
        XCTAssertEqual(UnikalizatorLogic.parseLine("unik_job_2_start=a.mp4 → b.mp4"), .job(index: 2, phase: "start", value: "a.mp4 → b.mp4"))
        XCTAssertEqual(UnikalizatorLogic.parseLine("unik_job_0_error=FFmpeg завершился с кодом 1."), .job(index: 0, phase: "error", value: "FFmpeg завершился с кодом 1."))
        XCTAssertEqual(UnikalizatorLogic.parseLine("unik_ffmpeg_progress=42"), .ffmpegProgress(42))
        XCTAssertEqual(UnikalizatorLogic.parseLine("unik_ffmpeg_message=Распаковываю…"), .ffmpegMessage("Распаковываю…"))
        XCTAssertNil(UnikalizatorLogic.parseLine("batch_slot_1_start=x"))
        XCTAssertNil(UnikalizatorLogic.parseLine("unik_job_x_start=y"))

        var jobs = UnikalizatorLogic.apply(.total(2), to: [])
        XCTAssertEqual(jobs.map(\.status), [.queued, .queued])
        jobs = UnikalizatorLogic.apply(.job(index: 0, phase: "start", value: "a → b"), to: jobs)
        jobs = UnikalizatorLogic.apply(.job(index: 0, phase: "progress", value: "55"), to: jobs)
        XCTAssertEqual(jobs[0].status, .running)
        XCTAssertEqual(jobs[0].percent, 55)
        jobs = UnikalizatorLogic.apply(.job(index: 0, phase: "done", value: "/out/b.mp4"), to: jobs)
        jobs = UnikalizatorLogic.apply(.job(index: 1, phase: "error", value: "сбой"), to: jobs)
        XCTAssertEqual(jobs[0].status, .done)
        XCTAssertEqual(jobs[0].outputPath, "/out/b.mp4")
        XCTAssertEqual(jobs[1].status, .error)
        XCTAssertEqual(jobs[1].message, "сбой")
    }

    func testOptionsEncodeWithTheKeysTheWorkerReads() throws {
        var options = UnikOptions()
        options.fps = 0
        options.ageMark = UnikOptions.AgeMark(enabled: true, geoId: "de-germany", position: "top")
        let data = try JSONEncoder().encode(WorkerRequest(command: "unik_process", url: nil, urls: nil, outputDirectory: "/out", headless: nil, mediaFilter: nil, files: nil, sources: ["/in/a.mp4"], options: options))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["command"] as? String, "unik_process")
        XCTAssertEqual(object["sources"] as? [String], ["/in/a.mp4"])
        XCTAssertNil(object["files"], "пустые поля не отправляются")
        let encoded = try XCTUnwrap(object["options"] as? [String: Any])
        XCTAssertEqual(encoded["formatPresetId"] as? String, "meta-story")
        XCTAssertEqual(encoded["fps"] as? Int, 0)
        for key in ["resize", "variations", "manual", "ageMark", "intro", "overlay", "audio", "metadata", "naming", "bitrate"] {
            XCTAssertNotNil(encoded[key], "воркер ждёт поле \(key)")
        }
        let age = try XCTUnwrap(encoded["ageMark"] as? [String: Any])
        XCTAssertEqual(age["geoId"] as? String, "de-germany")
        XCTAssertEqual(age["position"] as? String, "top")
        let variations = try XCTUnwrap(encoded["variations"] as? [String: Any])
        XCTAssertEqual(variations["styleIds"] as? [String], ["clean"])
        let decoded = try JSONDecoder().decode(UnikOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(decoded, options)
    }

    func testOptionsSavedBeforeAdjustStillDecode() throws {
        var options = UnikOptions()
        options.adjust = UnikOptions.Adjust(brightness: 0.1, contrast: 1.2, horizontalFlip: true)
        options.naming.geo = "DE"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any])
        let adjust = try XCTUnwrap(object["adjust"] as? [String: Any])
        XCTAssertEqual(adjust["brightness"] as? Double, 0.1)
        XCTAssertEqual(adjust["contrast"] as? Double, 1.2)
        XCTAssertEqual(adjust["horizontalFlip"] as? Bool, true)

        // Настройки и пресеты, сохранённые до появления яркости, контраста и отражения.
        object.removeValue(forKey: "adjust")
        let old = try JSONDecoder().decode(UnikOptions.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.adjust, UnikOptions.Adjust())
        XCTAssertEqual(old.naming.geo, "DE")
    }

    func testCatalogFromWorkerDecodes() throws {
        let json = """
        {"formatPresets":[{"id":"meta-story","name":"Instagram Stories 9x16","description":"d","output":{"container":"mp4","videoCodec":"h264","audioCodec":"aac"},
          "resize":{"width":1080,"height":1920,"fit":"cover","backgroundStyle":"bars","backgroundColor":"#111111"},"fps":30,"bitrate":"4M"}],
         "stylePresets":[{"id":"soft","label":"Мягкий","hint":"Теплее и мягче","hueShift":8,"saturation":1.18,"sharpness":0.28,"speedOffsetMs":0}],
         "fpsOptions":[25,30,50,60],"variationOptions":[1,2,3,5],
         "bitrateOptions":[{"value":"2M","label":"Стандарт","hint":"По умолчанию"}],
         "ageMarkGeos":[{"id":"au-australia","name":"AU - Australia"}]}
        """
        let catalog = try JSONDecoder().decode(UnikCatalog.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.formatPresets.first?.resize.height, 1920)
        XCTAssertEqual(catalog.stylePresets.first?.label, "Мягкий")
        XCTAssertEqual(catalog.stylePresets.first?.hueShift, 8)
        XCTAssertEqual(catalog.stylePresets.first?.saturation, 1.18)
        // Каталог старой версии без цвета стилей по-прежнему читается.
        let legacy = try JSONDecoder().decode(UnikStylePreset.self, from: Data(#"{"id":"clean","label":"Чистый","hint":"-"}"#.utf8))
        XCTAssertEqual(legacy.hueShift, 0)
        XCTAssertEqual(legacy.saturation, 1)
        XCTAssertEqual(catalog.ageMarkGeos.first?.id, "au-australia")
        XCTAssertEqual(catalog.bitrateOptions.first?.id, "2M")
    }

    func testWorkerResponseWithUnikalizatorItemsDecodes() throws {
        let json = """
        {"ok":true,"status":"unik_complete","message":"Готово: 1 из 1.","protocolVersion":2,
         "data":{"total":"1","done":"1","failed":"0","results":"[]"},"counts":{"found":0,"saved":0,"processed":0,"failed":0},
         "batchResults":[],"diagnostics":{"category":"unknown"},
         "items":[{"id":"/out/a.mp4","sourceURL":"/in/a.mp4","pageURL":"","localPath":"/out/a.mp4","metadataPath":"","mediaType":"video","createdAt":"2026-11-06T10:00:00.000Z"}],
         "logs":[]}
        """
        let response = try JSONDecoder().decode(WorkerResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.items.first?.localPath, "/out/a.mp4")
    }

    func testDescribeInspection() {
        let video = UnikInspection(ok: true, filePath: "a", kind: "video", durationSeconds: 75, width: 720, height: 1280, hasAudio: false, message: nil)
        XCTAssertEqual(UnikalizatorLogic.describe(video), "720×1280, 1:15, без звука")
        let broken = UnikInspection(ok: false, filePath: "a", kind: nil, durationSeconds: nil, width: nil, height: nil, hasAudio: nil, message: "битый")
        XCTAssertEqual(UnikalizatorLogic.describe(broken), "битый")
    }

    func testPresetsAreSavedReplacedAndRemovedByName() {
        var options = UnikOptions()
        options.fps = 60
        var list = UnikalizatorLogic.upsertingPreset([], name: "  Reels   DE  ", options: options)
        XCTAssertEqual(list.map(\.name), ["Reels DE"])
        options.fps = 25
        list = UnikalizatorLogic.upsertingPreset(list, name: "reels de", options: options)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].name, "reels de")
        XCTAssertEqual(list[0].options.fps, 25)
        XCTAssertEqual(UnikalizatorLogic.upsertingPreset(list, name: "   ", options: options), list)
        list = UnikalizatorLogic.upsertingPreset(list, name: "B", options: options)
        XCTAssertEqual(UnikalizatorLogic.removingPreset(list, name: "REELS DE").map(\.name), ["B"])
        var many: [UnikPreset] = []
        for index in 0..<(UnikalizatorLogic.maxPresets + 5) {
            many = UnikalizatorLogic.upsertingPreset(many, name: "P\(index)", options: options)
        }
        XCTAssertEqual(many.count, UnikalizatorLogic.maxPresets)
    }

    func testPresetsRoundTripAndIgnoreBrokenEntries() throws {
        var options = UnikOptions()
        options.ageMark = .init(enabled: true, geoId: "de-germany", position: "top")
        options.variations = .init(count: 3, styleIds: ["soft", "bright", "calm"], mode: "all-variations")
        let list = UnikalizatorLogic.upsertingPreset([], name: "DE 18+", options: options)
        let data = try JSONEncoder().encode(list)
        XCTAssertEqual(UnikalizatorLogic.decodePresets(data), list)

        let mixed = Data(#"[{"name":"Good","options":{}},{"name":"good"},{"oops":1},"text",{"name":" ","options":{}}]"#.utf8)
        // Лишние и сломанные записи отбрасываются; настройки без полей берутся по умолчанию, если это допускает разбор.
        let decoded = UnikalizatorLogic.decodePresets(mixed)
        XCTAssertLessThanOrEqual(decoded.count, 1)
        XCTAssertTrue(UnikalizatorLogic.decodePresets(nil).isEmpty)
        XCTAssertTrue(UnikalizatorLogic.decodePresets(Data("не json".utf8)).isEmpty)
    }
}
