import SwiftUI

extension ContentView {
    var sidebar: some View {
        List(selection: Binding<AppSection?>(
            get: { selectedSection },
            set: { if let section = $0 { selectedSection = section } }
        )) {
            Section("Библиотека") {
                ForEach([AppSection.main, .reels, .batch, .sorting]) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .padding(.vertical, 5)
                        .tag(section)
                }
            }
            Section {
                Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage)
                    .padding(.vertical, 5)
                    .tag(AppSection.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SaveMe")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if let version = model.readyUpdateVersion {
                    Button { model.installReadyUpdate() } label: {
                        Label("Обновить до \(version)", systemImage: "arrow.down.circle")
                    }
                    .saveMeGlassButton(prominent: true)
                    .disabled(model.isBusy)
                }
                Label(model.isDesignPreview ? "Предпросмотр дизайна" : "На вашем Mac", systemImage: model.isDesignPreview ? "eye" : "internaldrive")
                    .font(.caption.weight(.medium))
                Text("SaveMe · \(versionLabel)")
                    .font(.caption2).monospacedDigit()
            }
            .foregroundStyle(secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ToolbarContentBuilder
    var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.openSaveDirectory() } label: {
                Label("Открыть папку сохранения", systemImage: "folder")
            }
            .help("Открыть папку сохранения в Finder")
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button { Task { await model.refreshEnvironment() } } label: {
                Label("Проверить готовность", systemImage: "arrow.clockwise")
            }
            .help("Проверить браузер и вход в Instagram")
            .disabled(model.isBusy)
        }
    }

    var detailContent: some View {
        Group {
            switch selectedSection {
            case .main: homeTwoView
            case .batch: batchView
            case .reels: reelsView
            case .sorting: sortingView
            case .settings: settingsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, topContentInset)
        .background {
            windowBackground
                .saveMeExtendedBackground(enabled: !reduceTransparency)
        }
    }
}

private struct AppSectionFocusKey: FocusedValueKey {
    typealias Value = Binding<ContentView.AppSection>
}

extension FocusedValues {
    var appSection: Binding<ContentView.AppSection>? {
        get { self[AppSectionFocusKey.self] }
        set { self[AppSectionFocusKey.self] = newValue }
    }
}

struct AppNavigationCommands: Commands {
    @FocusedBinding(\.appSection) private var section

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Настройки…") { section = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(section == nil)
        }
        CommandMenu("Разделы") {
            Button("Stories") { section = .main }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(section == nil)
            Button("Reels") { section = .reels }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(section == nil)
            Button("Очередь профилей") { section = .batch }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(section == nil)
            Button("Сортировка") { section = .sorting }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(section == nil)
        }
    }
}
