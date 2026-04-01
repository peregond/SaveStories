import SwiftUI

extension ContentView {
    enum AppSection: String, CaseIterable, Identifiable {
        case main
        case batch
        case reels

        var id: String { rawValue }

        var title: String {
            switch self {
            case .main:
                "Главная"
            case .batch:
                "Списочная"
            case .reels:
                "Reels"
            }
        }

        var subtitle: String {
            switch self {
            case .main:
                "Новый стартовый сценарий"
            case .batch:
                "Очередь профилей"
            case .reels:
                "Скоро появится"
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
            }
        }
    }
}
