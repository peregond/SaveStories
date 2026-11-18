import SwiftUI

extension ContentView {
    var sidebar: some View {
        List(selection: Binding<AppSection?>(
            get: { selectedSection },
            set: { if let section = $0 { selectedSection = section } }
        )) {
            ForEach([AppSection.main, .reels, .unikalizator, .sorting]) { section in
                HStack(spacing: 6) {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.saveMe(.body, .medium))
                    Spacer(minLength: 0)
                    sidebarActivity(for: section)
                }
                .padding(.vertical, 6)
                .listItemTint(brandTint)
                .tag(section)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SaveMe")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if let version = model.readyUpdateVersion {
                    Button { model.installReadyUpdate() } label: {
                        Label(L("Обновить до {0}", version), systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .saveMeGlassButton(prominent: true)
                    .controlSize(.large)
                    .disabled(model.isBusy)
                }
                SidebarSettingsButton(
                    title: AppSection.settings.title,
                    systemImage: AppSection.settings.systemImage,
                    isSelected: selectedSection == .settings,
                    tint: brandTint
                ) { selectedSection = .settings }
                if model.isDesignPreview, !PreviewCapture.clean {
                    Label(L("Предпросмотр дизайна"), systemImage: "eye")
                        .font(.saveMe(.micro, .medium))
                        .foregroundStyle(secondaryText)
                        .padding(.horizontal, 10)
                }
                Text("SaveMe \(versionLabel)")
                    .font(.saveMe(.micro)).monospacedDigit()
                    .foregroundStyle(secondaryText)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    /// Раздел, в котором сейчас идёт работа, виден из любого другого: счётчик очереди или индикатор.
    @ViewBuilder
    func sidebarActivity(for section: AppSection) -> some View {
        switch section {
        case .main where model.batchIsRunning && model.batchTotalCount > 0:
            Text("\(model.batchCurrentIndex)/\(model.batchTotalCount)")
                .font(.saveMe(.micro, .medium))
                .monospacedDigit()
                .foregroundStyle(secondaryText)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: model.batchCurrentIndex)
                .accessibilityLabel(L("Скачиваю {0} из {1} — осталось {2}", model.batchCurrentIndex, model.batchTotalCount, model.batchRemainingCount))
        case .main where isStoriesDownloadInProgress,
             .reels where isReelsDownloadInProgress,
             .unikalizator where model.unikalizator.isRunning:
            ProgressView()
                .controlSize(.small)
                .transition(.opacity)
        default:
            EmptyView()
        }
    }

    @ToolbarContentBuilder
    var workspaceToolbar: some ToolbarContent {
        if model.isBusy {
            ToolbarItem(placement: .primaryAction) {
                Group {
                    if model.batchIsRunning && model.batchTotalCount > 0 {
                        ProgressView(value: Double(min(model.batchCurrentIndex, model.batchTotalCount)), total: Double(model.batchTotalCount))
                            .progressViewStyle(.circular)
                            .animation(.smooth(duration: 0.45), value: model.batchCurrentIndex)
                    } else {
                        ProgressView()
                    }
                }
                .controlSize(.small)
                .tint(brandTint)
                .frame(width: 28, height: 22)
                .help(model.currentStepLabel)
                .accessibilityLabel(model.currentStepLabel)
            }
        }
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
        .id(selectedSection)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.18), value: selectedSection)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationSubtitle(selectedSection.subtitle ?? "")
        .saveMeSoftScrollEdge()
        .background { windowBackground }
    }
}

/// Строка «Настройки» внизу боковой панели; повторяет системное выделение списка.
private struct SidebarSettingsButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.controlActiveState) private var controlActiveState

    private var isInactive: Bool { controlActiveState == .inactive }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.saveMe(.body, .medium))
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(isInactive ? Color.secondary : tint)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.10 : (isHovering ? 0.05 : 0)))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
