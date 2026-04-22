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
                "Списочная"
            case .reels:
                "Reels"
            case .sorting:
                "Сортировка"
            case .settings:
                "Настройки"
            }
        }

        var subtitle: String {
            switch self {
            case .main:
                "Загрузка stories из профилей тут"
            case .batch:
                "Очередь профилей"
            case .reels:
                "Выгрузка Reels тут"
            case .sorting:
                "Перенос, папки и ссылки"
            case .settings:
                "Воркер, сессия и обновления"
            }
        }

        var systemImage: String {
            switch self {
            case .main:
                "wand.and.stars.inverse"
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
    }
}
