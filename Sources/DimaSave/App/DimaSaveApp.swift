import SwiftUI

@main
struct DimaSaveApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1120, minHeight: 760)
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
