import SwiftUI

extension ContentView {
    enum AppSection: String, CaseIterable, Identifiable {
        case main
        case batch
        case reels
        case sorting
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .main:
                "Stories"
            case .batch:
                "Очередь профилей"
            case .reels:
                "Reels"
            case .sorting:
                "Сортировка"
            case .settings:
                "Настройки"
            }
        }

        var subtitle: String? {
            switch self {
            case .main:
                "Stories из профилей"
            case .batch:
                "Очередь профилей"
            case .reels:
                "Видео по ссылкам"
            case .sorting:
                "Перенос, папки и ссылки"
            case .settings:
                nil
            }
        }

        var systemImage: String {
            switch self {
            case .main:
                "rectangle.stack"
            case .batch:
                "list.bullet.rectangle.portrait"
            case .reels:
                "play.rectangle.on.rectangle"
            case .sorting:
                "folder.badge.gearshape"
            case .settings:
                "gearshape.fill"
            }
        }

        var sidebarEmoji: String? {
            switch self {
            case .main:
                "📱"
            case .batch:
                "📋"
            case .reels:
                "📹"
            case .sorting:
                "🗂️"
            case .settings:
                nil
            }
        }
    }
}
