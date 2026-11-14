import AppKit
@preconcurrency import UserNotifications

/// Системное уведомление о завершении загрузки — только когда окно приложения не на переднем плане.
enum CompletionNotifier {
    @MainActor
    static func notify(title: String, body: String) {
        // Без bundle identifier (запуск через `swift run`) центр уведомлений недоступен и падает при обращении.
        guard Bundle.main.bundleIdentifier != nil, !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
