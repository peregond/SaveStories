import SwiftUI

@main
struct SaveMeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 720)
                .task {
                    await model.prepare()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления...") {
                    Task { await model.checkForUpdates() }
                }
                .disabled(!model.canCheckForUpdates)
            }
        }
    }
}
