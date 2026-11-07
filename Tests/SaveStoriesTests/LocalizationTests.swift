import XCTest
@testable import SaveMe

final class LocalizationTests: XCTestCase {
    private func unescape(_ raw: String) -> String {
        var result = ""
        var iterator = raw.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else { result.append(character); continue }
            switch next {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            default: result.append(character); result.append(next)
            }
        }
        return result
    }

    /// Ключи из вызовов `L("…")` в исходниках приложения.
    private func usedKeys() throws -> [(file: String, key: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SaveStories", isDirectory: true)
        let pattern = try NSRegularExpression(pattern: #"\bL\("((?:\\.|[^"\\])*)""#)
        let skipped: Set<String> = ["EnglishStrings.swift", "Localization.swift"]
        var found: [(String, String)] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift", !skipped.contains(url.lastPathComponent) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { found.append((url.lastPathComponent, unescape(String(text[range])))) }
            }
        }
        return found
    }

    private func isCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    func testEveryRussianTextHasAnEnglishTranslation() throws {
        let keys = try usedKeys().filter { isCyrillic($0.key) }
        XCTAssertGreaterThan(keys.count, 400, "тексты в коде не найдены — проверьте путь к исходникам")
        let missing = keys.filter { EnglishStrings.table[$0.key] == nil }.map { "\($0.file): \($0.key)" }
        XCTAssertEqual(missing, [])
    }

    func testPlaceholdersMatchBetweenRussianAndEnglish() throws {
        let slots = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ text: String) -> [String] {
            slots.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }.sorted()
        }
        let broken = EnglishStrings.table.filter { placeholders($0.key) != placeholders($0.value) }.map(\.key)
        XCTAssertEqual(broken, [])
    }

    func testEnglishTextsAreNotLeftRussian() {
        let allowed = ["На перенос", "Перенос", "Исходники", "Уникализатор", "Язык", "Русский"]
        let bad = EnglishStrings.table.filter { entry in
            entry.value.trimmingCharacters(in: .whitespaces).isEmpty
                || (isCyrillic(entry.value) && !allowed.contains { entry.value.contains($0) })
        }.map(\.key)
        XCTAssertEqual(bad, [])
    }

    func testLocalizeSubstitutesValuesInBothLanguages() {
        XCTAssertEqual(Localizer.localize("Готово {0} из {1}", [2, 6], english: false), "Готово 2 из 6")
        XCTAssertEqual(Localizer.localize("Готово {0} из {1}", [2, 6], english: true), "Done 2 of 6")
        XCTAssertEqual(Localizer.localize("Выбрать", [], english: true), "Choose")
        XCTAssertEqual(Localizer.localize("Нет такого текста {0}", ["x"], english: true), "Нет такого текста x")
    }

    func testTranslateFindsExactAndTemplateMessages() {
        XCTAssertEqual(Localizer.translate("Сессия найдена.", english: false), "Сессия найдена.")
        XCTAssertEqual(Localizer.translate("Сессия найдена.", english: true), "Session found.")
        XCTAssertEqual(Localizer.translate("Для профиля dian.vegas1 сохранено файлов: 7.", english: true), "For profile dian.vegas1 files saved: 7.")
        XCTAssertEqual(Localizer.translate("Готово: 5 из 6, ошибок: 1.", english: true), "Done: 5 of 6, errors: 1.")
        XCTAssertEqual(Localizer.translate("Готово: 5 из 6.", english: true), "Done: 5 of 6.")
        XCTAssertEqual(Localizer.translate("Что-то совсем новое", english: true), "Что-то совсем новое")
        XCTAssertEqual(Localizer.translate("", english: true), "")
    }

    func testMentionsAnyIsCaseInsensitiveAcrossLanguages() {
        XCTAssertTrue("Ошибка установки".mentionsAny("ошиб", "error"))
        XCTAssertTrue("Installation ERROR".mentionsAny("ошиб", "error"))
        XCTAssertFalse("Готово".mentionsAny("ошиб", "error"))
    }
}
