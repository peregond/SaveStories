import Foundation

/// Язык интерфейса. Тексты в коде написаны по-русски и оборачиваются в `L("…")`: для английского ищется перевод
/// в `EnglishStrings.table`, нет перевода — остаётся русский. Подстановки: `L("Готово: {0} из {1}", done, total)`.
/// Язык читается при запуске, поэтому после смены в настройках нужен перезапуск приложения.
enum Localizer {
    static let languageKey = "SaveStories.interfaceLanguage"

    /// `--preview-language=en` — для снимков экрана в CI; иначе выбор пользователя ("en" — английский, по умолчанию русский).
    static let isEnglish: Bool = {
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-language=") }) {
            return argument.hasSuffix("=en")
        }
        return UserDefaults.standard.string(forKey: languageKey) == "en"
    }()

    static func setEnglish(_ enabled: Bool) {
        UserDefaults.standard.set(enabled ? "en" : "ru", forKey: languageKey)
    }

    static func localize(_ ru: String, _ args: [Any], english: Bool) -> String {
        let template = english ? (EnglishStrings.table[ru] ?? ru) : ru
        return fill(template, values: Dictionary(uniqueKeysWithValues: args.enumerated().map { ($0.offset, String(describing: $0.element)) }))
    }

    /// Подставляет значения вместо «{0}», «{1}»…; незнакомые скобки остаются как есть.
    static func fill(_ template: String, values: [Int: String]) -> String {
        guard !values.isEmpty, template.contains("{") else { return template }
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "{",
               let close = template[index...].firstIndex(of: "}"),
               let number = Int(template[template.index(after: index)..<close]),
               let value = values[number]
            {
                result += value
                index = template.index(after: close)
            } else {
                result.append(character)
                index = template.index(after: index)
            }
        }
        return result
    }

    // MARK: Готовые сообщения (ответы воркера и системные тексты)

    private struct Pattern: Sendable {
        let regex: NSRegularExpression
        let english: String
        let order: [Int]
        let weight: Int
    }

    private static let patterns: [Pattern] = {
        var list: [Pattern] = []
        for (russian, english) in EnglishStrings.table where russian.contains("{") {
            var order: [Int] = []
            var source = "^"
            var literal = ""
            var weight = 0
            var index = russian.startIndex
            while index < russian.endIndex {
                if russian[index] == "{",
                   let close = russian[index...].firstIndex(of: "}"),
                   let number = Int(russian[russian.index(after: index)..<close])
                {
                    source += NSRegularExpression.escapedPattern(for: literal) + "([\\s\\S]*?)"
                    weight += literal.count
                    literal = ""
                    order.append(number)
                    index = russian.index(after: close)
                } else {
                    literal.append(russian[index])
                    index = russian.index(after: index)
                }
            }
            source += NSRegularExpression.escapedPattern(for: literal) + "$"
            weight += literal.count
            if let regex = try? NSRegularExpression(pattern: source) {
                list.append(Pattern(regex: regex, english: english, order: order, weight: weight))
            }
        }
        // Сначала более конкретные шаблоны: «…из {1}, ошибок: {2}.» раньше «…из {1}.»
        return list.sorted { $0.weight > $1.weight }
    }()

    /// Перевод готового русского сообщения (например, ответа воркера). Нет перевода — исходный текст.
    static func translate(_ message: String, english: Bool) -> String {
        guard english, !message.isEmpty else { return message }
        if let exact = EnglishStrings.table[message] { return exact }
        let range = NSRange(message.startIndex..., in: message)
        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: message, range: range) else { continue }
            var values: [Int: String] = [:]
            for (position, slot) in pattern.order.enumerated() {
                if let found = Range(match.range(at: position + 1), in: message) { values[slot] = String(message[found]) }
            }
            return fill(pattern.english, values: values)
        }
        return message
    }
}

/// Текст интерфейса на выбранном языке: `L("Привет, {0}", name)`.
func L(_ ru: String, _ args: Any...) -> String {
    Localizer.localize(ru, args, english: Localizer.isEnglish)
}

/// Перевод готового сообщения (ответ воркера и т. п.) на выбранный язык.
func tr(_ message: String) -> String {
    Localizer.translate(message, english: Localizer.isEnglish)
}

extension String {
    /// Есть ли в тексте любая из подстрок (без учёта регистра). Для проверок по тексту статуса, который бывает русским или английским.
    func mentionsAny(_ needles: String...) -> Bool {
        let lowered = lowercased()
        return needles.contains { lowered.contains($0) }
    }
}
