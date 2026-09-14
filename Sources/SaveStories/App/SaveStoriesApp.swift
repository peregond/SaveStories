import SwiftUI

@main
struct SaveMeApp: App {
    @StateObject private var model = AppModel(
        isDesignPreview: ProcessInfo.processInfo.arguments.contains("--design-preview")
            || Bundle.main.object(forInfoDictionaryKey: "SaveMeDesignPreview") as? Bool == true
    )

    private var previewColorScheme: ColorScheme? {
        guard model.isDesignPreview else { return nil }
        switch Bundle.main.object(forInfoDictionaryKey: "SaveMePreviewAppearance") as? String {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some Scene {
        Window("SaveMe", id: "main") {
            ContentView()
                .environmentObject(model)
                .fontDesign(.rounded)
                .frame(minWidth: 860, minHeight: 620)
                .preferredColorScheme(previewColorScheme)
                .task {
                    await model.prepare()
                    if model.isDesignPreview,
                       Bundle.main.object(forInfoDictionaryKey: "SaveMePreviewOnboarding") as? Bool == true {
                        model.showRuntimeOnboarding = true
                    }
                }
        }
        .defaultSize(width: 1220, height: 840)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            AppNavigationCommands()
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…") {
                    Task { await model.checkForUpdates() }
                }
                .disabled(!model.canCheckForUpdates)
            }
        }
    }
}
