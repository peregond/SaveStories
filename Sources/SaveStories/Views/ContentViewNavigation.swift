import SwiftUI

extension ContentView {
    var sidebar: some View {
        List(selection: Binding<AppSection?>(
            get: { selectedSection },
            set: { if let section = $0 { selectedSection = section } }
        )) {
            ForEach([AppSection.main, .reels, .unikalizator, .sorting]) { section in
                Label(section.title, systemImage: section.systemImage)
                    .padding(.vertical, 5)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SaveMe")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().padding(.horizontal, 10)
                if let version = model.readyUpdateVersion {
                    Button { model.installReadyUpdate() } label: {
                        Label(L("Обновить до {0}", version), systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .saveMeGlassButton(prominent: true)
                    .disabled(model.isBusy)
                }
                SidebarSettingsButton(
                    title: AppSection.settings.title,
                    systemImage: AppSection.settings.systemImage,
                    isSelected: selectedSection == .settings
                ) { selectedSection = .settings }
                if model.isDesignPreview, !PreviewCapture.clean {
                    Label(L("Предпросмотр дизайна"), systemImage: "eye")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryText)
                        .padding(.horizontal, 10)
                }
                Text("SaveMe · \(versionLabel)")
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(secondaryText)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    @ToolbarContentBuilder
    var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.openSaveDirectory() } label: {
                Label(L("Открыть папку сохранения"), systemImage: "folder")
            }
            .help(L("Открыть папку сохранения в Finder"))
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button { Task { await model.refreshEnvironment() } } label: {
                Label(L("Проверить готовность"), systemImage: "arrow.clockwise")
            }
            .help(L("Проверить браузер и вход в Instagram"))
            .disabled(model.isBusy)
        }
    }

    var detailContent: some View {
        Group {
            switch selectedSection {
            case .main: homeTwoView
            case .reels: reelsView
            case .unikalizator: unikalizatorView
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

/// Sidebar-styled row pinned to the bottom-left; mirrors the List selection look.
private struct SidebarSettingsButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.controlActiveState) private var controlActiveState

    private var isInactive: Bool { controlActiveState == .inactive }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected && !isInactive ? Color.white : (isInactive ? Color.secondary : Color.accentColor))
            }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isSelected && !isInactive ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? (isInactive ? Color.primary.opacity(0.14) : Color.accentColor) : (isHovering ? Color.primary.opacity(0.08) : Color.clear))
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            Button(L("Настройки…")) { section = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(section == nil)
        }
        CommandMenu(L("Разделы")) {
            Button("Stories") { section = .main }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(section == nil)
            Button("Reels") { section = .reels }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(section == nil)
            Button(L("Уникализатор")) { section = .unikalizator }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(section == nil)
            Button(L("Сортировка")) { section = .sorting }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(section == nil)
        }
    }
}
