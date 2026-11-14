import SwiftUI

extension ContentView {
    enum AppSection: String, CaseIterable, Identifiable {
        case main
        case reels
        case unikalizator
        case sorting
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .main:
                "Stories"
            case .reels:
                "Reels"
            case .unikalizator:
                L("Уникализатор")
            case .sorting:
                L("Сортировка")
            case .settings:
                L("Настройки")
            }
        }

        var subtitle: String? {
            switch self {
            case .main:
                L("Stories из профилей")
            case .reels:
                L("Видео по ссылкам")
            case .unikalizator:
                L("Форматы, вариации, плашка 18+")
            case .sorting:
                L("Перенос, папки и ссылки")
            case .settings:
                nil
            }
        }

        var systemImage: String {
            switch self {
            case .main:
                "rectangle.stack"
            case .reels:
                "play.rectangle.on.rectangle"
            case .unikalizator:
                "wand.and.stars"
            case .sorting:
                "folder.badge.gearshape"
            case .settings:
                "gearshape.fill"
            }
        }
    }
}
