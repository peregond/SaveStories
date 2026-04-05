import SwiftUI

extension ContentView {
    enum AppSection: String, CaseIterable, Identifiable {
        case main
        case batch
        case reels
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
            case .settings:
                "gearshape.fill"
            }
        }
    }
}
