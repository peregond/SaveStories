import SwiftUI

private enum StoriesActionButtonKind {
    case neutral
    case primary
    case destructive
}

/// Плитка-кнопка внутри стеклянной панели: тонированная заливка без второго слоя стекла.
private struct StoriesActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let fill: Color
    let stroke: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous).strokeBorder(stroke, lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast
    @SceneStorage("navigation.section") private var storedSection = AppSection.main.rawValue
    @State var columnVisibility: NavigationSplitViewVisibility = .all
    @State var showingDownloadOptions = false

    var selectedSection: AppSection {
        get { AppSection(rawValue: storedSection) ?? .main }
        nonmutating set { storedSection = newValue.rawValue }
    }
    @State var showingConfetti = false
    @State var showingAllRecentLists = false
    @State var showingRuntimeDetails = false
    @State var showingLogsCopiedFeedback = false
    @State var showingHomeDiagnostics = false
    @State var showingPendingEmptyFolders = false
    @State var sortingRulesExpanded = false
    @State var sortingAdvancedExpanded = false
    @State var storiesInputExpanded = false
    /// Текущий шаг раздела «Уникализатор».
    @State var unikStep = 0
    @State var showingClearQueueConfirmation = false
    @State var showingDeleteEmptyFoldersConfirmation = false
    @State var unikDropTargeted = false

    var isDark: Bool { colorScheme == .dark }
    var reduceMotion: Bool {
        systemReduceMotion || (model.isDesignPreview && Bundle.main.object(forInfoDictionaryKey: "SaveMePreviewReduceMotion") as? Bool == true)
    }

    let sidebarWidth: CGFloat = 220
    let cardCornerRadius: CGFloat = SaveMeMetrics.cardRadius
    let controlCornerRadius: CGFloat = SaveMeMetrics.controlRadius
    let itemCornerRadius: CGFloat = SaveMeMetrics.itemRadius
    let innerCornerRadius: CGFloat = SaveMeMetrics.innerRadius
    let topContentInset: CGFloat = 0
    let homeSummaryCardHeight: CGFloat = 170

    func contentHorizontalPadding(for width: CGFloat) -> CGFloat {
        width < 760 ? 20 : 28
    }

    func isCompactHomeLayout(for width: CGFloat) -> Bool {
        width < 760
    }

    /// Плотные поверхности вместо стекла: «Уменьшение прозрачности» или «Увеличение контраста».
    var prefersSolidSurfaces: Bool { reduceTransparency || contrast == .increased || SaveMeRendering.forceSolid }

    var brandTint: Color { SaveMePalette.brand(dark: isDark) }
    var primaryText: Color { Color(nsColor: .labelColor) }
    var secondaryText: Color {
        contrast == .increased ? primaryText : SaveMePalette.secondaryText(dark: isDark)
    }
    var tertiaryText: Color { secondaryText }
    var quaternaryText: Color { secondaryText }
    var cardFill: Color { Color(nsColor: .controlBackgroundColor) }
    /// «Колодец» для ввода и путей внутри стеклянной панели.
    var inputFill: Color {
        prefersSolidSurfaces ? Color(nsColor: .textBackgroundColor) : SaveMePalette.well(dark: isDark)
    }
    /// Заливка второстепенных кнопок и меток внутри панели.
    var controlFill: Color {
        prefersSolidSurfaces ? Color(nsColor: .quaternaryLabelColor).opacity(0.14) : SaveMePalette.control(dark: isDark)
    }
    var secondaryButtonTint: Color { brandTint }
    var prominentButtonTint: Color { SaveMePalette.brandFill(dark: isDark) }
    var queueActionTint: Color { SaveMePalette.brandFill(dark: isDark) }
    var cardStroke: Color {
        contrast == .increased ? Color(nsColor: .separatorColor) : SaveMePalette.hairline(dark: isDark)
    }

    var versionLabel: String {
        if model.isDesignPreview, let override = PreviewCapture.versionOverride { return override }
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildVersion))"
    }

    var reelsLinkCount: Int {
        model.parsedReelLinks(from: model.reelsInput).count
    }

    var batchProfileInputCount: Int {
        model.normalizedBatchLinks(from: model.batchInput).count
    }

    var queuedPendingCount: Int {
        model.batchQueue.filter { $0.status == .pending || $0.status == .running }.count
    }

    var queuedCompletedCount: Int {
        model.batchQueue.filter { $0.status == .completed }.count
    }

    var queuedFailedCount: Int {
        model.batchQueue.filter { $0.status == .failed }.count
    }

    var isReelsDownloadInProgress: Bool {
        let combined = "\(model.statusTitle) \(model.currentStepLabel)".lowercased()
        return model.isBusy && combined.contains("reels")
    }

    var isStoriesDownloadInProgress: Bool {
        model.batchIsRunning || (model.isDownloadActivityInProgress && !isReelsDownloadInProgress)
    }

    var selectedDownloadModeDescription: String {
        switch model.downloadMode {
        case .background:
            return L("Браузер скрыт, работает незаметно")
        case .visible:
            return L("Открывается окно Chromium, можно наблюдать")
        }
    }

    var selectedMediaSelectionDescription: String {
        switch model.mediaSelectionMode {
        case .all:
            return L("Скачиваются все сторис")
        case .videoOnly:
            return L("Фото пропускаются")
        }
    }

    var globalStatusTint: Color {
        if model.isBusy {
            return SaveMePalette.info.opacity(0.82)
        }
        if model.statusTitle.mentionsAny("ошиб", "error", "fail") || !model.workerReady {
            return SaveMePalette.danger.opacity(0.82)
        }
        if !model.sessionReady {
            return SaveMePalette.warning.opacity(0.82)
        }
        return SaveMePalette.success.opacity(0.82)
    }

    var pendingEmptyFolderNames: [String] {
        model.pendingEmptyStoryFolders.map(\.lastPathComponent)
    }

    var sortingRuleCount: Int {
        model.folderRoutingRules
            .split(whereSeparator: \.isNewline)
            .filter { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                return !line.isEmpty && !line.hasPrefix("#") && line.contains("=")
            }
            .count
    }

    var sortingHasSource: Bool {
        model.sortingSourceDirectory != nil
    }

    var sortingHasDestination: Bool {
        model.distributionRootDirectory != nil
    }

    var sortingHasResults: Bool {
        !model.postProcessedItems.isEmpty
    }

    var sortingCanUndo: Bool {
        model.postProcessedItems.contains { $0.originalPath != $0.currentPath }
    }

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: sidebarWidth, max: 280)
            } detail: {
                detailContent
                    .navigationTitle(selectedSection.title)
                    .toolbar { workspaceToolbar }
            }
            .navigationSplitViewStyle(.balanced)
            .disabled(model.showRuntimeOnboarding || model.showEmptyFolderCleanupPrompt)

            if showingConfetti {
                ConfettiOverlayView()
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(4)
            }


        }
        .sheet(isPresented: $model.showRuntimeOnboarding, onDismiss: { model.dismissRuntimeOnboarding() }) {
            VStack(spacing: 0) {
                ScrollView { runtimeOnboardingContent }
                Divider()
                runtimeOnboardingActions.padding(20)
            }
            .fontDesign(.rounded)
            .frame(width: 540, height: 620)
            .interactiveDismissDisabled(model.isBusy)
        }
        .sheet(isPresented: $model.showEmptyFolderCleanupPrompt) {
            emptyFolderCleanupPrompt
                .fontDesign(.rounded)
                .frame(width: 520)
                .fixedSize(horizontal: false, vertical: true)
                .interactiveDismissDisabled()
        }
        .tint(queueActionTint)
        .onAppear {
            if model.isDesignPreview, let raw = PreviewCapture.section, let section = AppSection(rawValue: raw) {
                selectedSection = section
                // Восстановление состояния окна срабатывает позже onAppear и возвращало прошлый раздел.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    selectedSection = section
                }
            }
            if model.isDesignPreview, let step = PreviewCapture.unikStep {
                unikStep = step
            }
            if model.isDesignPreview, PreviewCapture.wantsSamples {
                model.unikalizator.loadPreviewSamples()
            }
        }
        .focusedSceneValue(\.appSection, Binding(get: { selectedSection }, set: { selectedSection = $0 }))
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { showingConfetti = false }
        }
        .alert(L("Нужен вход в Instagram"), isPresented: $model.showLoginPrompt) {
            Button(L("Не сейчас"), role: .cancel) {
                model.dismissLoginPrompt()
            }
            Button(L("Открыть браузер")) {
                Task { await model.login() }
            }
        } message: {
            Text(L("Для первой выгрузки stories войдите в Instagram через браузер приложения. Окно останется открытым, пока вход не будет завершён."))
        }
        .alert(item: $model.emptyFolderCleanupReport) { report in
            Alert(
                title: Text(report.title),
                message: Text(report.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: model.batchRemainingCount) { _, _ in updateDockBadge() }
        .onChange(of: model.batchIsRunning) { _, _ in updateDockBadge() }
        .task {
            if model.isDesignPreview, PreviewCapture.wantsDemoDownload {
                await model.runPreviewDemoDownload()
            }
        }
        .onChange(of: model.showEmptyFolderCleanupPrompt) { _, isShown in
            if !isShown {
                showingPendingEmptyFolders = false
            }
        }
        .onChange(of: model.celebrationToken) { _, newValue in
            if newValue > 0, !model.isDesignPreview {
                CompletionNotifier.notify(title: L("Загрузка завершена"), body: L("Сохранено файлов: {0}", model.savedStoriesCount))
            }
            guard newValue > 0, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showingConfetti = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    showingConfetti = false
                }
            }
        }
    }

    /// Сколько профилей осталось — на значке в Dock, пока окно свёрнуто или закрыто другим.
    func updateDockBadge() {
        NSApp.dockTile.badgeLabel = model.batchIsRunning && model.batchRemainingCount > 0 ? "\(model.batchRemainingCount)" : nil
    }

    var runtimeOnboardingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: runtimeOnboardingIcon)
                    .font(.saveMe(.display, .semibold))
                    .foregroundStyle(runtimeOnboardingTint)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(runtimeOnboardingTint.opacity(isDark ? 0.20 : 0.14))
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Первый запуск"))
                        .font(.saveMe(.display, .semibold))
                        .foregroundStyle(primaryText)

                    Text(L("Для скачивания нужен встроенный браузер. Установите его один раз — SaveMe подготовит всё автоматически."))
                        .font(.saveMe(.body, .medium))
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(runtimeOnboardingStages, id: \.self) { stage in
                    runtimeOnboardingStageRow(stage)
                }
            }

            statusInlineNote(
                title: model.runtimeSetupStage == .failed ? L("Ошибка установки") : L("Состояние"),
                message: model.runtimeSetupErrorMessage ?? model.runtimeSetupMessage
            )

        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var runtimeOnboardingActions: some View {
        HStack(spacing: 10) {
            if model.runtimeSetupStage == .ready {
                Button {
                    model.dismissRuntimeOnboarding()
                    Task { await model.login() }
                } label: {
                    Label(L("Войти в Instagram"), systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .saveMeGlassButton(prominent: true)

                Button {
                    model.dismissRuntimeOnboarding()
                } label: {
                    Text(L("Позже"))
                        .frame(maxWidth: .infinity)
                }
                .saveMeGlassButton()
            } else {
                Button {
                    Task { await model.bootstrapEnvironment() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isBusy && model.runtimeSetupStage != .failed {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(model.runtimeSetupStage == .failed ? L("Повторить установку") : L("Установить движок"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .saveMeGlassButton(prominent: true)
                .disabled(model.isBusy && model.runtimeSetupStage != .failed)

                Button {
                    model.dismissRuntimeOnboarding()
                } label: {
                    Text(L("Не сейчас"))
                        .frame(maxWidth: .infinity)
                }
                .saveMeGlassButton()
                .disabled(model.isBusy)
            }
        }
    }

    var runtimeOnboardingStages: [AppModel.RuntimeSetupStage] {
        [.folders, .node, .worker, .packages, .browser, .ready]
    }

    var runtimeOnboardingIcon: String {
        switch model.runtimeSetupStage {
        case .ready:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        default:
            "arrow.down.circle.fill"
        }
    }

    var runtimeOnboardingTint: Color {
        switch model.runtimeSetupStage {
        case .ready:
            SaveMePalette.success.opacity(0.86)
        case .failed:
            SaveMePalette.danger.opacity(0.82)
        default:
            prominentButtonTint
        }
    }

    func runtimeOnboardingStageRow(_ stage: AppModel.RuntimeSetupStage) -> some View {
        let status = runtimeOnboardingStatus(for: stage)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(status.tint.opacity(isDark ? 0.20 : 0.14))
                    .frame(width: 30, height: 30)

                if status.isSpinning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: status.symbol)
                        .font(.saveMe(.body, .bold))
                        .foregroundStyle(status.tint)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(stage.title)
                    .font(.saveMe(.body, .semibold))
                    .foregroundStyle(primaryText)

                Text(stage.detail)
                    .font(.saveMe(.label, .medium))
                    .foregroundStyle(tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                .fill(status.tint.opacity(status.isCurrent ? (isDark ? 0.12 : 0.08) : 0.04))
        )
    }

    struct RuntimeOnboardingStatus {
        let symbol: String
        let tint: Color
        let isCurrent: Bool
        let isSpinning: Bool
    }

    func runtimeOnboardingStatus(for stage: AppModel.RuntimeSetupStage) -> RuntimeOnboardingStatus {
        if model.runtimeSetupStage == .failed {
            let failedStage = model.runtimeSetupFailedStage ?? .folders
            let stageOrder = runtimeOnboardingOrder(stage)
            let failedOrder = runtimeOnboardingOrder(failedStage)
            if stageOrder < failedOrder {
                return RuntimeOnboardingStatus(symbol: "checkmark", tint: SaveMePalette.success.opacity(0.86), isCurrent: false, isSpinning: false)
            }
            return RuntimeOnboardingStatus(
                symbol: stageOrder == failedOrder ? "exclamationmark" : "circle",
                tint: stageOrder == failedOrder ? SaveMePalette.danger.opacity(0.82) : tertiaryText,
                isCurrent: stageOrder == failedOrder,
                isSpinning: false
            )
        }

        if model.runtimeSetupStage == .ready {
            return RuntimeOnboardingStatus(
                symbol: "checkmark",
                tint: SaveMePalette.success.opacity(0.86),
                isCurrent: stage == .ready,
                isSpinning: false
            )
        }

        let currentOrder = runtimeOnboardingOrder(model.runtimeSetupStage)
        let stageOrder = runtimeOnboardingOrder(stage)
        if stageOrder < currentOrder {
            return RuntimeOnboardingStatus(symbol: "checkmark", tint: SaveMePalette.success.opacity(0.86), isCurrent: false, isSpinning: false)
        }
        if stageOrder == currentOrder && model.runtimeSetupStage != .welcome {
            return RuntimeOnboardingStatus(symbol: "circle", tint: prominentButtonTint, isCurrent: true, isSpinning: model.isBusy)
        }
        return RuntimeOnboardingStatus(symbol: "circle", tint: tertiaryText, isCurrent: false, isSpinning: false)
    }

    func runtimeOnboardingOrder(_ stage: AppModel.RuntimeSetupStage) -> Int {
        switch stage {
        case .welcome:
            0
        case .folders:
            1
        case .node:
            2
        case .worker:
            3
        case .packages:
            4
        case .browser:
            5
        case .ready:
            6
        case .failed:
            7
        }
    }

    var emptyFolderCleanupPrompt: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Удалить пустые папки?"))
                .font(.saveMe(.heading, .semibold))
                .foregroundStyle(primaryText)

            Text(L("После выгрузки stories найдены пустые папки профилей. Удалить их и оставить только папки с сохранёнными файлами?"))
                .font(.saveMe(.title, .medium))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $showingPendingEmptyFolders) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pendingEmptyFolderNames, id: \.self) { name in
                            Text(name)
                                .font(.saveMe(.label, .medium, mono: true))
                                .foregroundStyle(primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .overlay(alignment: .bottom) { Divider() }
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxHeight: 180)
            } label: {
                Text(showingPendingEmptyFolders ? L("Скрыть список папок") : L("Показать список папок"))
                    .font(.saveMe(.body, .semibold))
                    .foregroundStyle(primaryText)
            }
            .tint(prominentButtonTint)

            HStack(spacing: 12) {
                Button {
                    model.dismissEmptyFolderCleanupPrompt()
                } label: {
                    Text(L("Не удалять"))
                        .frame(maxWidth: .infinity)
                }
                .saveMeGlassButton()

                Button {
                    Task { await model.removePendingEmptyStoryFolders() }
                } label: {
                    Text(L("Удалить"))
                        .frame(maxWidth: .infinity)
                }
                .saveMeGlassButton(prominent: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    var downloadOptionsSummary: String {
        var parts = [model.mediaSelectionMode.title, model.downloadMode.title]
        if model.notionInfluencerSourceEnabled { parts.append(L("Очередь из Notion")) }
        return parts.joined(separator: ", ")
    }

    func homeTwoComposerCard(compact: Bool) -> some View {
        card(L("Новая загрузка"), symbol: "arrow.down.to.line") {
            VStack(alignment: .leading, spacing: 16) {
                storiesInputEditor

                HStack(spacing: 12) {
                    Button {
                        model.addBatchProfiles()
                    } label: {
                        Label(L("В очередь"), systemImage: "plus")
                    }
                    .saveMeGlassButton()
                    .disabled(batchProfileInputCount == 0 || model.isBusy)
                    .help(L("Добавить введённые профили в очередь"))

                    Spacer(minLength: 0)

                    Menu {
                        Button(L("Запомнить очередь"), systemImage: "bookmark") { model.rememberCurrentBatchList() }
                            .disabled(model.batchQueue.isEmpty || model.isBusy)
                        Button(L("Очистить поле"), systemImage: "xmark") { model.batchInput = "" }
                            .disabled(model.batchInput.isEmpty || model.isBusy)
                    } label: {
                        Label(L("Ещё"), systemImage: "ellipsis")
                    }
                    .menuStyle(.button)
                    .saveMeGlassButton()
                    .fixedSize()
                }

                SaveMeGlassGroup(spacing: 12) {
                    HStack(spacing: 12) {
                        storiesDownloadButton
                        if model.batchIsRunning {
                            storiesStopButton
                                .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.batchIsRunning)
                if model.notionInfluencerSourceEnabled {
                    Label(
                        batchProfileInputCount > 0
                            ? L("Скачаем введённые профили и текущую очередь. Notion не заменит список.")
                            : L("Перед запуском очередь заменится актуальным списком из Notion."),
                        systemImage: "info.circle"
                    )
                    .font(.saveMe(.micro))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(queueActionTint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Папка сохранения"))
                            .font(.saveMe(.micro))
                            .foregroundStyle(secondaryText)
                        Text(model.saveDirectory.lastPathComponent)
                            .font(.saveMe(.body, .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.saveDirectory.path)
                    }
                    Spacer(minLength: 8)
                    Button(L("Изменить…")) { model.chooseSaveDirectory() }
                        .saveMeGlassButton()
                        .disabled(model.isBusy)
                }

                DisclosureGroup(isExpanded: $showingDownloadOptions) {
                    VStack(alignment: .leading, spacing: 14) {
                        storiesMediaSelectionPicker
                        storiesDownloadModePicker
                    }
                    notionInfluencerSourceControl
                        .padding(.top, 2)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Параметры загрузки")).font(.saveMe(.body, .medium))
                        Text(downloadOptionsSummary)
                            .font(.saveMe(.micro)).foregroundStyle(secondaryText)
                    }
                }
            }
        }
    }

    func homeTwoQueueCard(compact: Bool) -> some View {
        card(L("Очередь"), symbol: "list.bullet") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    queueSummaryBadge(text: L("Ждёт {0}", queuedPendingCount), tint: SaveMePalette.warning)
                    queueSummaryBadge(text: L("Готово {0}", queuedCompletedCount), tint: SaveMePalette.success)
                    queueSummaryBadge(text: L("Ошибок {0}", queuedFailedCount), tint: SaveMePalette.danger)
                    Spacer(minLength: 0)
                    if !model.batchQueue.isEmpty {
                        Button {
                            showingClearQueueConfirmation = true
                        } label: {
                            Label(L("Очистить очередь"), systemImage: "trash")
                        }
                        .saveMeGlassButton()
                        .controlSize(.small)
                        .disabled(model.isBusy)
                        .transition(.opacity)
                        .confirmationDialog(L("Очистить очередь?"), isPresented: $showingClearQueueConfirmation) {
                            Button(L("Очистить очередь"), role: .destructive) { model.clearBatchQueue() }
                            Button(L("Отмена"), role: .cancel) {}
                        } message: {
                            Text(L("Из очереди будут убраны все профили: {0}.", model.batchQueue.count))
                        }
                    }
                }

                if model.batchQueue.isEmpty {
                    Text(L("Добавьте профили в поле загрузки или выберите сохранённый набор."))
                        .font(.saveMe(.body, .medium))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if model.batchTotalCount > 0 {
                        batchProgressStripe
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(model.batchQueue) { item in
                                    batchQueueItem(item)
                                        .id(item.id)
                                        .transition(.opacity)
                                }
                            }
                            .animation(.smooth(duration: 0.3), value: model.batchQueue)
                        }
                        .frame(height: min(CGFloat(model.batchQueue.count) * 54, 340))
                        .onChange(of: model.batchCurrentIndex) { _, _ in
                            // Список сам подъезжает к профилю, который скачивается сейчас.
                            guard let running = model.batchQueue.first(where: { $0.status == .running }) else { return }
                            withAnimation(.smooth(duration: 0.4)) {
                                proxy.scrollTo(running.id, anchor: .center)
                            }
                        }
                    }
                }

                if !model.batchQueue.isEmpty {
                    Text(L("После запуска список сохранится в «Недавних наборах»."))
                        .font(.saveMe(.label))
                        .foregroundStyle(secondaryText)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: model.batchTotalCount > 0)
        .animation(.smooth(duration: 0.3), value: model.batchQueue.isEmpty)
    }

    func recentListsCard(compact: Bool) -> some View {
        card(L("Недавние наборы"), symbol: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                if model.recentBatchLists.isEmpty {
                    Text(L("Здесь появятся сохранённые и недавно запущенные наборы профилей."))
                        .font(.saveMe(.body, .medium))
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(displayedRecentBatchLists) { list in
                            recentListCard(list, compact: compact)
                        }
                    }

                    if model.recentBatchLists.count > 3 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingAllRecentLists.toggle()
                            }
                        } label: {
                            Text(showingAllRecentLists ? L("Свернуть") : L("Показать ещё"))
                                .font(.saveMe(.body, .semibold))
                                .foregroundStyle(primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Capsule(style: .continuous).fill(controlFill))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var displayedRecentBatchLists: [AppModel.RecentBatchList] {
        showingAllRecentLists ? model.recentBatchLists : Array(model.recentBatchLists.prefix(3))
    }

    func recentListCard(_ list: AppModel.RecentBatchList, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.title)
                        .font(.saveMe(.body, .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(list.subtitle)
                        Text(formattedRecentListDate(list.createdAt))
                    }
                        .font(.saveMe(.micro, .medium))
                        .foregroundStyle(tertiaryText)
                }

                Spacer(minLength: 0)

                Button {
                    model.removeRecentBatchList(id: list.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.saveMe(.micro, .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(controlFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Удалить набор {0}", list.title))
                .help(L("Удалить набор"))
                .disabled(model.isBusy)
            }

            Text(list.urls.prefix(2).joined(separator: "\n"))
                .font(.saveMe(.micro, .medium, mono: true))
                .foregroundStyle(secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            if compact {
                VStack(spacing: 8) {
                    recentActionButton(L("Добавить в очередь"), systemImage: "plus") {
                        model.applyRecentBatchList(list)
                    }

                    recentActionButton(L("Заменить очередь"), systemImage: "arrow.triangle.swap") {
                        model.replaceQueueWithRecentBatchList(list)
                    }
                    .disabled(model.isBusy)
                }
            } else {
                HStack(spacing: 8) {
                    recentActionButton(L("Добавить в очередь"), systemImage: "plus") {
                        model.applyRecentBatchList(list)
                    }

                    recentActionButton(L("Заменить очередь"), systemImage: "arrow.triangle.swap") {
                        model.replaceQueueWithRecentBatchList(list)
                    }
                    .disabled(model.isBusy)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    func recentActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        ghostButton(title, systemImage: systemImage, action: action)
    }


    /// Общий ход очереди: полоса плавно дотягивается до нового значения, цифры перекатываются.
    var batchProgressStripe: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Скачиваю {0} из {1} — осталось {2}", model.batchCurrentIndex, model.batchTotalCount, model.batchRemainingCount))
                .font(.saveMe(.body, .semibold))
                .monospacedDigit()
                .foregroundStyle(primaryText)
                .contentTransition(.numericText())

            ProgressView(value: Double(min(model.batchCurrentIndex, max(model.batchTotalCount, 1))), total: Double(max(model.batchTotalCount, 1)))
                .progressViewStyle(.linear)
                .tint(brandTint)

            if !model.batchCurrentURL.isEmpty {
                Text(model.batchCurrentURL)
                    .font(.saveMe(.micro, .medium, mono: true))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .id(model.batchCurrentURL)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.batchCurrentIndex)
        .animation(.smooth(duration: 0.45), value: model.batchTotalCount)
    }



    var statusCards: some View {
        HStack(spacing: 12) {
            statusCard(title: L("Движок"), presentation: workerStatusPresentation)
            statusCard(title: L("Сессия"), presentation: sessionStatusPresentation)
        }
    }




    var homeStatusHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            homeStatusBadge
            HStack(spacing: 8) {
                topStatusChip(title: L("Движок"), isReady: model.workerReady)
                topStatusChip(title: "Instagram", isReady: model.sessionReady)
                Spacer(minLength: 0)
                Button {
                    Task { await model.login() }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .saveMeGlassButton()
                .accessibilityLabel(model.sessionReady ? L("Обновить вход в Instagram") : L("Войти в Instagram"))
                .help(model.sessionReady ? L("Обновить вход в Instagram") : L("Войти в Instagram"))
                .disabled(model.isBusy)
            }
        }
    }

    func topStatusChip(title: String, isReady: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isReady ? SaveMePalette.success : SaveMePalette.warning)
                .font(.saveMe(.micro))

            Text(title)
                .font(.saveMe(.micro, .semibold))
                .foregroundStyle(isReady ? secondaryText : primaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isReady ? L("Готово") : L("Требуется настройка"))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill((isReady ? SaveMePalette.success : SaveMePalette.warning).opacity(isDark ? 0.12 : 0.10))
        )
    }

    var homeStatusBadge: some View {
        let isError = model.statusTitle.mentionsAny("ошиб", "error", "fail")
        let isDone = model.statusTitle.mentionsAny("готов", "ready", "done")
        let title: String
        let tint: Color

        if model.isBusy {
            title = isStoriesDownloadInProgress ? L("Идёт загрузка") : L("Подготовка")
            tint = SaveMePalette.info.opacity(0.82)
        } else if isError {
            title = L("Ошибка")
            tint = SaveMePalette.danger.opacity(0.82)
        } else if isDone {
            title = L("Готово")
            tint = SaveMePalette.success.opacity(0.82)
        } else {
            title = L("Ожидание")
            tint = SaveMePalette.neutral.opacity(0.78)
        }

        return HStack(spacing: 8) {
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Text(title)
                .font(.saveMe(.label, .semibold))
                .contentTransition(.opacity)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(isDark ? 0.14 : 0.10))
        )
        .animation(.smooth(duration: 0.3), value: title)
    }


    var postProcessingCard: some View {
        card(L("Сортировка"), symbol: "folder.badge.gearshape") {
            VStack(alignment: .leading, spacing: 16) {
                sortingOverviewCard

                sortingStepCard(
                    number: "1",
                    title: L("Укажите, где находится папка «На перенос»"),
                    detail: L("Отсюда приложение возьмёт файлы для раскладки."),
                    isActive: true,
                    isDone: sortingHasSource
                ) {
                    horizontalMonospaceField(
                        model.sortingSourceDirectory?.path ?? L("Папка ещё не выбрана."),
                        fontSize: 12
                    )
                    .frame(height: 52)

                    HStack(spacing: 10) {
                        button(L("Выбрать папку"), systemImage: "tray.full", prominent: true) {
                            model.chooseSortingSourceDirectory()
                        }

                        button(L("Открыть"), systemImage: "folder") {
                            model.openSortingSourceDirectory()
                        }
                        .disabled(!sortingHasSource)
                    }
                }

                sortingStepCard(
                    number: "2",
                    title: L("Выберите папку WhiteList INF Исходники"),
                    detail: L("Сюда файлы будут разложены по подпапкам."),
                    isActive: sortingHasSource,
                    isDone: sortingHasDestination
                ) {
                    horizontalMonospaceField(
                        model.distributionRootDirectory?.path ?? L("Папка ещё не выбрана."),
                        fontSize: 12
                    )
                    .frame(height: 52)

                    HStack(spacing: 10) {
                        button(L("Выбрать папку"), systemImage: "folder.badge.plus", prominent: sortingHasSource) {
                            model.chooseDistributionRootDirectory()
                        }

                        button(L("Открыть"), systemImage: "folder") {
                            model.openDistributionRootDirectory()
                        }
                        .disabled(!sortingHasDestination)
                    }
                }

                sortingStepCard(
                    number: "3",
                    title: L("Добавьте правила при необходимости"),
                    detail: L("Укажите страну или полный путь для конкретного блогера."),
                    isActive: sortingHasSource && sortingHasDestination,
                    isDone: sortingRuleCount > 0
                ) {
                    notionRoutingRulesSourceControl

                    DisclosureGroup(isExpanded: $sortingRulesExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            textEditorCard(
                                text: $model.folderRoutingRules,
                                placeholder: L("nick = Germany (DE)\nnick2 = Australia (AU)/Папка блогера")
                            )
                            .frame(height: 124)
                            .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))

                            Text(L("Если указать только страну, приложение само добавит внутрь папку блогера: `nick = Germany (DE)` → `Germany (DE)/nick`."))
                                .font(.saveMe(.label, .medium))
                                .foregroundStyle(quaternaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(L("Запомнено блогеров: {0}. Список обновляется после правил и каждого переноса.", model.rememberedBloggers.count))
                                .font(.saveMe(.label, .semibold))
                                .foregroundStyle(secondaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            if !model.rememberedBloggers.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(model.rememberedBloggers.prefix(6)) { blogger in
                                        Text("\(blogger.countryFolder): \(blogger.username)")
                                            .font(.saveMe(.label, .medium))
                                            .foregroundStyle(quaternaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Text(sortingRuleCount == 0 ? L("Открыть правила") : L("Правил: {0}", sortingRuleCount))
                                .font(.saveMe(.body, .semibold))
                                .foregroundStyle(primaryText)
                            Spacer(minLength: 0)
                        }
                    }
                    .tint(prominentButtonTint)
                }

                sortingStepCard(
                    number: "4",
                    title: L("Разложите файлы"),
                    detail: L("Нажмите основную кнопку. Дополнительный вариант — ниже."),
                    isActive: sortingHasSource && sortingHasDestination,
                    isDone: sortingHasResults
                ) {
                    HStack(spacing: 12) {
                        statPill(
                            title: L("Последняя выгрузка"),
                            value: model.latestSessionDownloadedItems.count,
                            accent: SaveMePalette.warning.opacity(0.78)
                        )
                        statPill(
                            title: L("Готово"),
                            value: model.postProcessedItems.count,
                            accent: SaveMePalette.info.opacity(0.78)
                        )
                    }

                    Text(model.postProcessingSummary)
                        .font(.saveMe(.body, .medium))
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    button(L("Разложить из папки Перенос"), systemImage: "arrow.right.doc.on.clipboard", prominent: true) {
                        Task { await model.distributeFilesFromSortingSource() }
                    }
                    .disabled(!(sortingHasSource && sortingHasDestination) || model.isRefreshingNotionRoutingRules)

                    button(L("Отмена переноса"), systemImage: "arrow.uturn.backward", prominent: false) {
                        Task { await model.undoLastDistribution() }
                    }
                    .disabled(!sortingCanUndo)

                    DisclosureGroup(isExpanded: $sortingAdvancedExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Используйте это, если нужно разложить файлы из последней загрузки приложения, без папки Перенос."))
                                .font(.saveMe(.label, .medium))
                                .foregroundStyle(quaternaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            button(L("Из последней загрузки"), systemImage: "square.stack.3d.down.forward") {
                                Task { await model.distributeLatestDownloadedFiles() }
                            }
                            .disabled(!sortingHasDestination)
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Text(L("Дополнительно"))
                                .font(.saveMe(.body, .semibold))
                                .foregroundStyle(primaryText)
                            Spacer(minLength: 0)
                        }
                    }
                    .tint(prominentButtonTint)
                }

                sortingStepCard(
                    number: "5",
                    title: L("Скопируйте готовый результат"),
                    detail: L("Drive-ссылки копируются дайджестом: страна, блогер, ссылки."),
                    isActive: sortingHasResults,
                    isDone: false
                ) {
                    Text(model.googleDriveLinkSummary)
                        .font(.saveMe(.label, .medium))
                        .foregroundStyle(quaternaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        button(L("Скопировать список"), systemImage: "doc.on.doc", prominent: sortingHasResults) {
                            model.copyPostProcessedReport()
                        }
                        .disabled(!sortingHasResults)

                        button(L("Скопировать ссылки"), systemImage: "link.badge.plus") {
                            Task { await model.exportGoogleDriveLinks() }
                        }
                        .disabled(!sortingHasResults)
                    }

                    Text(L("Если у файла не найдутся данные Google Drive, приложение попробует получить ссылку через Finder."))
                        .font(.saveMe(.label, .medium))
                        .foregroundStyle(quaternaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    button(L("Открыть доступы"), systemImage: "gearshape") {
                        model.openSystemSettings()
                    }
                }
            }
        }
    }

    /// Отдельная утилита, не шаг сортировки: удаляет пустые подпапки в выбранной папке.
    var emptyFolderCleanupCard: some View {
        card(L("Удалить пустые папки"), symbol: "folder.badge.minus") {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Работает отдельно от сортировки и не трогает папку «На перенос»."))
                    .font(.saveMe(.label))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                horizontalMonospaceField(
                    model.emptyFolderCleanupDirectory?.path ?? L("Папка ещё не выбрана."),
                    fontSize: SaveMeTextRole.label.rawValue
                )
                .frame(height: 44)

                HStack(spacing: 10) {
                    button(L("Выбрать папку"), systemImage: "folder.badge.gearshape") {
                        model.chooseEmptyFolderCleanupDirectory()
                    }

                    button(L("Открыть"), systemImage: "folder") {
                        model.openEmptyFolderCleanupDirectory()
                    }
                    .disabled(model.emptyFolderCleanupDirectory == nil)
                }

                button(L("Удалить пустые папки"), systemImage: "trash") {
                    showingDeleteEmptyFoldersConfirmation = true
                }
                .disabled(model.emptyFolderCleanupDirectory == nil)
                .confirmationDialog(L("Удалить пустые папки?"), isPresented: $showingDeleteEmptyFoldersConfirmation) {
                    Button(L("Удалить"), role: .destructive) {
                        Task { await model.removeEmptyFoldersInCleanupDirectory() }
                    }
                    Button(L("Отмена"), role: .cancel) {}
                } message: {
                    Text(L("Пустые подпапки в «{0}» будут удалены. Папки с файлами останутся.", model.emptyFolderCleanupDirectory?.lastPathComponent ?? ""))
                }

                Text(model.emptyFolderCleanupSummary)
                    .font(.saveMe(.label))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var sortingOverviewCard: some View {
        HStack(alignment: .top, spacing: 16) {
            sortingOverviewPill(title: L("Источник"), state: sortingHasSource ? L("Выбран") : L("Не выбран"), tint: sortingHasSource ? SaveMePalette.success : SaveMePalette.warning)
            sortingOverviewPill(title: L("Назначение"), state: sortingHasDestination ? L("Выбрано") : L("Не выбрано"), tint: sortingHasDestination ? SaveMePalette.success : SaveMePalette.warning)
            sortingOverviewPill(title: L("Результат"), state: sortingHasResults ? L("Готов") : L("Пусто"), tint: sortingHasResults ? SaveMePalette.success : secondaryText)
        }
    }

    func sortingOverviewPill(title: String, state: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state)
                .font(.saveMe(.body, .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.saveMe(.label))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Шаг сортировки: номер, заголовок и содержимое; шаги разделены линией, без вложенных плиток.
    func sortingStepCard<Content: View>(
        number: String,
        title: String,
        detail: String,
        isActive: Bool,
        isDone: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(.saveMe(.body, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isDone ? SaveMePalette.success : (isActive ? brandTint : secondaryText))
                    .frame(width: 16, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.saveMe(.title, .semibold))
                        .foregroundStyle(primaryText)

                    Text(isDone ? L("Готово") + ". " + detail : detail)
                        .font(.saveMe(.label))
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.leading, 26)
            .opacity(isActive || isDone ? 1 : 0.6)
        }
    }

    /// Журнал событий. Пока событий нет — одна строка вместо пустой панели.
    func logsCard(maxHeight: CGFloat? = nil) -> some View {
        card(L("Логи"), symbol: "text.alignleft", padding: 0) {
            if model.logs.isEmpty {
                Text(L("Лог пока пуст."))
                    .font(.saveMe(.label, .medium))
                    .foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SaveMeMetrics.cardPadding)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            model.copyLogs()
                            showingLogsCopiedFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                showingLogsCopiedFeedback = false
                            }
                        } label: {
                            Label(showingLogsCopiedFeedback ? L("Скопировано") : L("Скопировать логи"), systemImage: showingLogsCopiedFeedback ? "checkmark" : "doc.on.doc")
                        }
                        .saveMeGlassButton()
                        .controlSize(.small)
                    }
                    .padding(.horizontal, SaveMeMetrics.cardPadding)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(model.logs.reversed().enumerated()), id: \.offset) { _, line in
                                Text(cleanedLogLine(line))
                                    .font(.saveMe(.label, .medium, mono: true))
                                    .foregroundStyle(logTint(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.horizontal, SaveMeMetrics.cardPadding)
                        .padding(.bottom, SaveMeMetrics.cardPadding)
                    }
                    .frame(maxWidth: .infinity, maxHeight: maxHeight ?? 320, alignment: .topLeading)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: model.logs.isEmpty)
    }


    func homeDiagnosticsCard(maxHeight: CGFloat? = nil) -> some View {
        card(L("Диагностика"), symbol: "stethoscope", padding: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if model.statusTitle.mentionsAny("ошиб", "error", "fail") {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.saveMe(.title, .semibold))
                            .foregroundStyle(SaveMePalette.danger)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.logs.first.map(cleanedLogLine) ?? L("Технические сообщения появятся после первой операции."))
                            .font(.saveMe(.label, .medium))
                            .foregroundStyle(tertiaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingHomeDiagnostics.toggle()
                        }
                    } label: {
                        Label(showingHomeDiagnostics ? L("Скрыть") : L("Открыть"), systemImage: showingHomeDiagnostics ? "chevron.up" : "chevron.down")
                    }
                    .saveMeGlassButton()
                    .controlSize(.small)
                }
                .padding(.horizontal, SaveMeMetrics.cardPadding)

                if showingHomeDiagnostics {
                    Divider()
                        .overlay(cardStroke)
                        .padding(.horizontal, SaveMeMetrics.cardPadding)

                    HStack(spacing: 12) {
                        Text(L("Последние события"))
                            .font(.saveMe(.label, .bold))
                            .foregroundStyle(quaternaryText)

                        Spacer(minLength: 0)

                        Button {
                            model.copyLogs()
                            showingLogsCopiedFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                showingLogsCopiedFeedback = false
                            }
                        } label: {
                            Label(showingLogsCopiedFeedback ? L("Скопировано") : L("Скопировать"), systemImage: showingLogsCopiedFeedback ? "checkmark" : "doc.on.doc")
                        }
                        .saveMeGlassButton()
                        .controlSize(.small)
                    }
                    .padding(.horizontal, SaveMeMetrics.cardPadding)

                    if model.logs.isEmpty {
                        Text(L("Лог пока пуст."))
                            .font(.saveMe(.label, .medium))
                            .foregroundStyle(secondaryText)
                            .padding(.horizontal, SaveMeMetrics.cardPadding)
                            .padding(.bottom, SaveMeMetrics.cardPadding)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(model.logs.reversed().enumerated()), id: \.offset) { index, line in
                                        Text(cleanedLogLine(line))
                                            .font(.saveMe(.label, .medium, mono: true))
                                            .foregroundStyle(logTint(for: line))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                            .id(index)
                                    }
                                }
                                .padding(.horizontal, SaveMeMetrics.cardPadding)
                                .padding(.bottom, SaveMeMetrics.cardPadding)
                            }
                            .frame(maxWidth: .infinity, maxHeight: maxHeight ?? 320, alignment: .topLeading)
                            .onAppear {
                                proxy.scrollTo(model.logs.count - 1, anchor: .bottom)
                            }
                            .onChange(of: model.logs.count) { _, newCount in
                                guard newCount > 0 else { return }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(newCount - 1, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, showingHomeDiagnostics ? 0 : SaveMeMetrics.cardPadding)
        }
    }

    var runtimeCard: some View {
        settingsCard(L("Техническая информация"), symbol: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                Text(runtimeSummaryHeadline)
                    .font(.saveMe(.body, .medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup(L("Показать детали"), isExpanded: $showingRuntimeDetails) {
                    horizontalMonospaceField(
                        model.runtimeSummary.isEmpty ? L("Информация о среде появится после проверки воркера.") : model.runtimeSummary,
                        fontSize: 12
                    )
                    .padding(.top, 8)
                    .transition(.opacity)
                }
                .font(.saveMe(.body, .medium))
                .tint(prominentButtonTint)

                button(L("Открыть папку среды"), systemImage: "internaldrive") {
                    model.openRuntimeDirectory()
                }
            }
        }
    }

    var languageCard: some View {
        settingsCard("Language / Язык", symbol: "globe") {
            LanguageSetting(secondaryText: secondaryText)
        }
    }

    var updatesCard: some View {
        settingsCard(L("Обновления"), symbol: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                statusInlineNote(
                    title: L("Автообновление"),
                    message: model.updateSummary
                )

                Toggle(
                    isOn: Binding(
                        get: { model.automaticUpdatesEnabled },
                        set: { model.setAutomaticUpdatesEnabled($0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Проверять и скачивать автоматически"))
                            .font(.saveMe(.body, .semibold))
                            .foregroundStyle(primaryText)

                        Text(L("При запуске SaveMe проверит обновление и подготовит его к установке."))
                            .font(.saveMe(.label, .medium))
                            .foregroundStyle(tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .disabled(!model.canCheckForUpdates)

                if model.canCheckForUpdates {
                    Button {
                        Task { await model.checkForUpdates() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isCheckingForUpdates {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }

                            Text(L("Проверить обновления"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .saveMeGlassButton(prominent: true)
                    .disabled(model.isCheckingForUpdates)
                } else {
                    Text(L("Обновления пока недоступны в этой сборке"))
                        .font(.saveMe(.body, .medium))
                        .foregroundStyle(quaternaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    var powerCard: some View {
        settingsCard(L("Во время выгрузки"), symbol: "moon.zzz") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $model.preventSleepDuringDownloads) {
                    Text(L("Не давать Mac засыпать и гасить экран"))
                        .font(.saveMe(.body, .semibold))
                        .foregroundStyle(primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)

                if !model.preventSleepDuringDownloads {
                    statusInlineNote(
                        title: L("Внимание"),
                        message: L("Если Mac уснёт или заблокирует экран во время длинной выгрузки, скачивание stories или Reels может прерваться.")
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    var sessionCard: some View {
        settingsCard(L("Подключение к Instagram"), symbol: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Если среда ещё не подготовлена, установите компоненты прямо отсюда. После этого можно открыть браузер для входа и проверить сессию."))
                    .font(.saveMe(.body, .medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                statusInlineNote(
                    title: L("Авторизация"),
                    message: L("Браузер для входа держится открытым, пока Instagram не выдаст активную сессию или пока не истечёт таймаут.")
                )

                if model.hasEmbeddedRuntime {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.saveMe(.title, .semibold))
                            .foregroundStyle(SaveMePalette.success.opacity(0.86))

                        Text(L("Всё встроено — дополнительная установка не нужна"))
                            .font(.saveMe(.body, .semibold))
                            .foregroundStyle(primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    if !model.hasEmbeddedRuntime {
                        button(L("Установить компоненты"), systemImage: "arrow.down.circle") {
                            Task { await model.bootstrapEnvironment() }
                        }

                        button(L("Проверить готовность"), systemImage: "bolt.horizontal.circle") {
                            Task { await model.refreshEnvironment() }
                        }
                    }

                    button(L("Войти в Instagram"), systemImage: "person.crop.circle.badge.checkmark", prominent: true) {
                        Task { await model.login() }
                    }

                    button(L("Проверить сессию"), systemImage: "checkmark.shield") {
                        Task { await model.checkSession() }
                    }
                }
            }
        }
    }


    var storiesDownloadModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Режим браузера"))
                .font(.saveMe(.micro))
                .foregroundStyle(tertiaryText)

            Picker(L("Режим браузера"), selection: $model.downloadMode) {
                ForEach(AppModel.DownloadMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedDownloadModeDescription)
                .font(.saveMe(.body, .medium))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: model.downloadMode)
    }

    var storiesMediaSelectionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Что сохранять"))
                .font(.saveMe(.micro))
                .foregroundStyle(tertiaryText)

            Picker(L("Что сохранять"), selection: $model.mediaSelectionMode) {
                ForEach(AppModel.MediaSelectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedMediaSelectionDescription)
                .font(.saveMe(.body, .medium))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: model.mediaSelectionMode)
    }


    var reelsComposerCard: some View {
        reelsCard(L("Ссылки на Reels"), symbol: "link") {
            VStack(alignment: .leading, spacing: 14) {
                reelsInputEditor

                HStack(spacing: 10) {
                    Button {
                        Task { await model.downloadReels() }
                    } label: {
                        HStack(spacing: 8) {
                            if isReelsDownloadInProgress {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L("Загружаю..."))
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                Text(L("Скачать"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .saveMeGlassButton(prominent: true)
                    .disabled(reelsLinkCount == 0 || model.isBusy)
                    .opacity(reelsLinkCount == 0 || model.isBusy ? 0.72 : 1)

                    Button {
                        model.reelsInput = ""
                    } label: {
                        Label(L("Очистить"), systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .saveMeGlassButton()
                    .disabled(model.isBusy || model.reelsInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(model.isBusy || model.reelsInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.72 : 1)
                }

                Text(L("Reels скачиваются отдельным потоком и не зависят от сценария сторис."))
                    .font(.saveMe(.label, .medium))
                    .foregroundStyle(quaternaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isBusy)
    }

    var reelsInputEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.reelsInput)
                .accessibilityLabel(L("Ссылки на Reels"))
                .font(.saveMe(.body, .medium, mono: true))
                .scrollContentBackground(.hidden)
                .foregroundStyle(primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .background(Color.clear)
                .frame(minHeight: 160)

            if model.reelsInput.isEmpty {
                Text(L("Например:\nhttps://www.instagram.com/reel/DMabc123/\nhttps://www.instagram.com/reel/DMxyz456/"))
                    .font(.saveMe(.body, .medium, mono: true))
                    .foregroundStyle(tertiaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }

            if !model.reelsInput.isEmpty {
                Button {
                    model.reelsInput = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.saveMe(.micro, .bold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(controlFill)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .transition(.opacity)
            }

            Text(L("Ссылок: {0}", reelsLinkCount))
                .font(.saveMe(.micro, .semibold))
                .foregroundStyle(quaternaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(controlFill)
                )
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .background(fieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: reelsLinkCount)
    }

    var reelsDestinationCard: some View {
        reelsCard(L("Куда сохранять"), symbol: "folder") {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.saveDirectory.path)
                    .font(.saveMe(.body, .medium, mono: true))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))

                HStack(spacing: 10) {
                    Button {
                        model.chooseSaveDirectory()
                    } label: {
                        Label(L("Выбрать папку"), systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .saveMeGlassButton()

                    Button {
                        model.openSaveDirectory()
                    } label: {
                        Label(L("Показать в Finder"), systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .saveMeGlassButton()
                }
            }
        }
    }

    var reelsActivityPanel: some View {
        VStack(alignment: .leading, spacing: SaveMeMetrics.sectionSpacing) {
            reelsActivityHeader
            reelsDownloadsCard
            reelsLogsCard()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: model.isBusy)
    }

    var reelsActivityHeader: some View {
        card(L("Состояние"), symbol: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 10) {
                reelsSessionBadge

                Text(model.lastResult)
                    .font(.saveMe(.body, .medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isBusy {
                    HStack(spacing: 8) {
                        liveIndicatorDot(size: 8)

                        Text(model.currentStepLabel)
                            .font(.saveMe(.label, .semibold))
                            .foregroundStyle(tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    var reelsSessionBadge: some View {
        let ready = model.sessionReady
        return HStack(spacing: 6) {
            Image(systemName: ready ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.exclamationmark")
                .font(.saveMe(.micro, .semibold))

            Text(ready ? L("Сессия активна") : L("Нет сессии"))
                .font(.saveMe(.micro, .semibold))
        }
        .foregroundStyle(ready ? SaveMePalette.success.opacity(0.88) : SaveMePalette.danger.opacity(0.82))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill((ready ? SaveMePalette.success : SaveMePalette.danger).opacity(isDark ? 0.16 : 0.10))
        )
    }

    var reelsDownloadsCard: some View {
        reelsCard(L("Последние загрузки"), symbol: "tray.full", padding: 0) {
            Group {
                if model.downloadedItems.isEmpty {
                    Text(L("Пока ничего нет"))
                        .font(.saveMe(.label, .medium))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SaveMeMetrics.cardPadding)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.downloadedItems.prefix(20)) { item in
                                reelsDownloadRow(item)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(.smooth(duration: 0.35), value: model.downloadedItems.count)
                        .padding(SaveMeMetrics.cardPadding)
                    }
                    .frame(maxHeight: 260)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .transition(.opacity)
        }
    }

    func reelsDownloadRow(_ item: WorkerItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(URL(fileURLWithPath: item.localPath).lastPathComponent)
                        .font(.saveMe(.body, .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)

                    Text(item.localPath)
                        .font(.saveMe(.micro, .medium, mono: true))
                        .foregroundStyle(tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Button {
                    model.revealDownloadedItem(at: item.localPath)
                } label: {
                    Image(systemName: "folder")
                        .font(.saveMe(.label, .semibold))
                        .frame(width: 28, height: 28)
                }
                .saveMeGlassButton()
                .help(L("Показать в Finder"))
            }

            HStack(spacing: 8) {
                Text(formattedFileSize(for: item.localPath))
                Text(formattedDownloadTime(item.createdAt))
            }
            .font(.saveMe(.micro, .medium))
            .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    func reelsLogsCard(maxHeight: CGFloat? = nil) -> some View {
        logsCard(maxHeight: maxHeight ?? 280)
    }

    func logTint(for line: String) -> Color {
        let normalized = line.lowercased()
        if normalized.contains("error") || normalized.contains("failed") {
            return SaveMePalette.danger.opacity(0.84)
        }
        if normalized.contains("ready") || normalized.contains("saved") {
            return SaveMePalette.success.opacity(0.84)
        }
        return secondaryText
    }

    func formattedFileSize(for path: String) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? NSNumber
        else {
            return L("Размер неизвестен")
        }

        return ByteCountFormatter.string(fromByteCount: fileSize.int64Value, countStyle: .file)
    }

    func formattedDownloadTime(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else {
            return raw
        }

        return date.formatted(date: .omitted, time: .shortened)
    }

    func formattedRecentListDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    func cleanedLogLine(_ line: String) -> String {
        let pattern = #"/[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        var result = line
        let matches = regex.matches(in: line, range: range).reversed()
        for match in matches {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let path = String(result[swiftRange])
            result.replaceSubrange(swiftRange, with: URL(fileURLWithPath: path).lastPathComponent)
        }
        return result
    }

    var storiesInputEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.batchInput)
                    .font(.saveMe(.body, .regular, mono: true))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(primaryText)
                    .padding(10)
                    .frame(height: storiesInputExpanded ? 300 : 116)
                    .accessibilityLabel(L("Профили Instagram"))
                    .accessibilityHint(L("По одной ссылке или имени пользователя на строку"))
                if model.batchInput.isEmpty {
                    Text(L("Ссылка на профиль или @username\nПо одному на строку"))
                        .font(.saveMe(.body, .regular, mono: true))
                        .foregroundStyle(secondaryText)
                        .padding(.horizontal, 16).padding(.vertical, 18)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            Divider()
            HStack {
                Text(L("Профилей: {0}", batchProfileInputCount))
                    .font(.saveMe(.micro)).monospacedDigit()
                    .foregroundStyle(secondaryText)
                Spacer()
                if shouldShowStoriesInputExpandButton {
                    Button(storiesInputExpanded ? L("Свернуть") : L("Раскрыть")) {
                        storiesInputExpanded.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.saveMe(.micro))
                }
                if !model.batchInput.isEmpty {
                    Button { model.batchInput = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(secondaryText)
                    .accessibilityLabel(L("Очистить поле профилей"))
                    .help(L("Очистить поле профилей"))
                    .disabled(model.isBusy)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: controlCornerRadius).strokeBorder(cardStroke))
    }

    var shouldShowStoriesInputExpandButton: Bool {
        batchProfileInputCount > 5 || model.batchInput.count > 180 || storiesInputExpanded
    }

    var notionInfluencerSourceControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $model.notionInfluencerSourceEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Обновлять очередь из Notion"))
                        .font(.saveMe(.body, .semibold))
                        .foregroundStyle(primaryText)

                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .tint(queueActionTint)
            .disabled(model.isBusy || model.isRefreshingNotionInfluencers)

            HStack(spacing: 10) {
                if model.isRefreshingNotionInfluencers {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: model.notionInfluencerSourceEnabled ? "arrow.triangle.2.circlepath.circle.fill" : "link.circle")
                        .foregroundStyle(model.notionInfluencerSourceEnabled ? queueActionTint : tertiaryText)
                }

                Text(model.notionInfluencerSourceSummary)
                    .font(.saveMe(.label, .medium))
                    .foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await model.refreshNotionInfluencerQueue(replaceQueue: true, force: true) }
                } label: {
                    Text(L("Обновить"))
                        .font(.saveMe(.label, .semibold))
                }
                .saveMeGlassButton()
                .controlSize(.small)
                .disabled(model.isBusy || model.isRefreshingNotionInfluencers)
            }
        }
    }

    var notionRoutingRulesSourceControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $model.notionRoutingRulesSourceEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Обновлять правила из Notion"))
                        .font(.saveMe(.body, .semibold))
                        .foregroundStyle(primaryText)

                    Text(L("Перед сортировкой приложение обновит правила не чаще раза в день и заменит список ниже."))
                        .font(.saveMe(.label, .medium))
                        .foregroundStyle(tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .tint(prominentButtonTint)
            .disabled(model.isBusy || model.isRefreshingNotionRoutingRules)

            HStack(spacing: 10) {
                if model.isRefreshingNotionRoutingRules {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: model.notionRoutingRulesSourceEnabled ? "arrow.triangle.2.circlepath.circle.fill" : "link.circle")
                        .foregroundStyle(model.notionRoutingRulesSourceEnabled ? prominentButtonTint : tertiaryText)
                }

                Text(model.notionRoutingRulesSourceSummary)
                    .font(.saveMe(.label, .medium))
                    .foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await model.refreshNotionRoutingRules(force: true) }
                } label: {
                    Text(L("Обновить"))
                        .font(.saveMe(.label, .semibold))
                }
                .saveMeGlassButton()
                .controlSize(.small)
                .disabled(model.isBusy || model.isRefreshingNotionRoutingRules)
            }
        }
    }

    var storiesDownloadButton: some View {
        storiesActionButton(
            isStoriesDownloadInProgress ? L("Загружаем…") : (model.notionInfluencerSourceEnabled && batchProfileInputCount == 0 ? L("Скачать из Notion") : L("Скачать Stories")),
            systemImage: "arrow.down",
            kind: .primary,
            isEnabled: (!model.batchQueue.isEmpty || batchProfileInputCount > 0 || model.notionInfluencerSourceEnabled) && !model.isBusy && !model.isRefreshingNotionInfluencers,
            isProgressing: isStoriesDownloadInProgress
        ) {
            Task { await model.downloadStoriesFromInput() }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .help(L("Начать загрузку Stories (⌘↩)"))
    }

    var storiesStopButton: some View {
        storiesActionButton(
            L("Остановить"),
            systemImage: "stop",
            kind: .destructive,
            isEnabled: model.batchIsRunning
        ) {
            model.stopBatchDownloads()
        }
    }


    @ViewBuilder
    private func storiesActionButton(
        _ title: String,
        systemImage: String,
        kind: StoriesActionButtonKind = .neutral,
        isEnabled: Bool,
        isProgressing: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let label = HStack(spacing: 8) {
            if isProgressing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .font(.saveMe(.body, .semibold))
                    .frame(width: 16)
            }

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .font(.saveMe(.body, .semibold))
        .frame(maxWidth: .infinity)

        switch kind {
        case .primary:
            Button(action: action) { label.padding(.vertical, 3) }
                .saveMeGlassButton(prominent: true)
                .controlSize(.large)
                .disabled(!isEnabled)
        case .destructive:
            Button(role: .destructive, action: action) { label.padding(.vertical, 3) }
                .saveMeGlassButton(tint: SaveMePalette.danger.opacity(isDark ? 0.55 : 0.45))
                .controlSize(.large)
                .disabled(!isEnabled)
        case .neutral:
            Button(action: action) { label.padding(.vertical, 3) }
                .saveMeGlassButton()
                .controlSize(.large)
                .disabled(!isEnabled)
        }
    }

    /// Второстепенное действие внутри панели: капсула с лёгкой заливкой.
    func ghostButton(_ title: String, systemImage: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.saveMe(.label, .semibold))
                Text(title)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)
            }
            .font(.saveMe(.body, .medium))
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(StoriesActionButtonStyle(
            fill: tint.map { $0.opacity(isDark ? 0.16 : 0.09) } ?? controlFill,
            stroke: (tint ?? primaryText).opacity(tint == nil ? 0.10 : 0.22)
        ))
        .foregroundStyle(tint ?? primaryText)
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.55 : 1)
        .frame(maxWidth: .infinity)
    }

    func queueSummaryBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.saveMe(.label, .medium))
            .monospacedDigit()
            .foregroundStyle(secondaryText)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.35), value: text)
    }

    func reelsCard<Content: View>(_ title: String, symbol: String? = nil, padding: CGFloat = SaveMeMetrics.cardPadding, @ViewBuilder content: () -> Content) -> some View {
        card(title, symbol: symbol, padding: padding, content: content)
    }

    struct SettingsStatusPresentation {
        let symbol: String
        let status: String
        let accent: Color
        let backgroundTint: Color
    }

    var workerStatusPresentation: SettingsStatusPresentation {
        let summary = model.workerSummary.lowercased()
        if model.workerReady {
            return SettingsStatusPresentation(
                symbol: "bolt.fill",
                status: L("Готов"),
                accent: SaveMePalette.success.opacity(0.86),
                backgroundTint: SaveMePalette.success.opacity(isDark ? 0.16 : 0.10)
            )
        }

        let isError = summary.mentionsAny("ошиб", "не удалось", "process", "error", "could not", "failed")
        return SettingsStatusPresentation(
            symbol: "bolt.fill",
            status: L("Ошибка"),
            accent: isError ? SaveMePalette.danger.opacity(0.82) : SaveMePalette.neutral.opacity(0.78),
            backgroundTint: isError ? SaveMePalette.danger.opacity(isDark ? 0.14 : 0.08) : SaveMePalette.neutral.opacity(isDark ? 0.12 : 0.07)
        )
    }

    var sessionStatusPresentation: SettingsStatusPresentation {
        let summary = model.sessionSummary.lowercased()
        if model.sessionReady {
            return SettingsStatusPresentation(
                symbol: "person.crop.circle.badge.checkmark",
                status: L("Готов"),
                accent: SaveMePalette.success.opacity(0.86),
                backgroundTint: SaveMePalette.success.opacity(isDark ? 0.16 : 0.10)
            )
        }

        let isError = summary.mentionsAny("ошиб", "timeout", "error", "failed")
        return SettingsStatusPresentation(
            symbol: "person.crop.circle.badge.checkmark",
            status: isError ? L("Ошибка") : L("Нет сессии"),
            accent: isError ? SaveMePalette.danger.opacity(0.82) : SaveMePalette.neutral.opacity(0.78),
            backgroundTint: isError ? SaveMePalette.danger.opacity(isDark ? 0.14 : 0.08) : SaveMePalette.neutral.opacity(isDark ? 0.12 : 0.07)
        )
    }

    var runtimeSummaryHeadline: String {
        guard !model.runtimeSummary.isEmpty else {
            return L("Данные о движке появятся после проверки.")
        }

        var fields: [String: String] = [:]
        for line in model.runtimeSummary.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                fields[parts[0]] = parts[1]
            }
        }

        let runtimeKind = (fields["worker_runtime"] ?? "node").lowercased() == "python" ? "Python" : "Node"
        let browserLabel = (fields["browsers"] ?? "").contains("ms-playwright") ? "ms-chromium" : "browser runtime"
        return "\(runtimeKind), Playwright, \(browserLabel)"
    }

    func statusCard(title: String, presentation: SettingsStatusPresentation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: presentation.symbol)
                .font(.saveMe(.body, .semibold))
                .foregroundStyle(presentation.accent)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.status)
                    .font(.saveMe(.body, .semibold))
                    .foregroundStyle(primaryText)
                    .contentTransition(.opacity)
                Text(title)
                    .font(.saveMe(.label))
                    .foregroundStyle(secondaryText)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.2), value: presentation.status)
    }


    var stepTracker: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(model.isBusy ? prominentButtonTint.opacity(isDark ? 0.24 : 0.14) : Color.clear)
                    .frame(width: 30, height: 30)
                    .scaleEffect(model.isBusy ? 1.0 : 0.88)
                    .opacity(model.isBusy ? 1 : 0)

                Image(systemName: model.isBusy ? "point.3.connected.trianglepath.dotted" : "sparkle")
                    .font(.saveMe(.body, .semibold))
                    .foregroundStyle(model.isBusy ? prominentButtonTint : tertiaryText)
                    .symbolEffect(.pulse.byLayer, options: .repeating, isActive: model.isBusy && !reduceMotion)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L("Текущий шаг"))
                    .font(.saveMe(.micro, .bold))
                    .foregroundStyle(quaternaryText)

                if model.isBusy && !reduceMotion {
                    TimelineView(.periodic(from: .now, by: 0.6)) { context in
                        Text(animatedBusyStepLabel(at: context.date))
                            .font(.saveMe(.body, .semibold))
                            .foregroundStyle(primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(model.currentStepLabel)
                        .font(.saveMe(.body, .medium))
                        .foregroundStyle(primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if model.isBusy && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.24)) { context in
                    busyStepActivityIndicator(at: context.date)
                }
            }
        }
    }

    func animatedBusyStepLabel(at date: Date) -> String {
        let base = model.currentStepLabel.isEmpty ? L("Идёт подготовка выгрузки") : model.currentStepLabel
        let phase = Int(date.timeIntervalSinceReferenceDate / 0.6) % 4
        return base + String(repeating: ".", count: phase)
    }

    func busyStepActivityIndicator(at date: Date) -> some View {
        let phase = Int(date.timeIntervalSinceReferenceDate / 0.24) % 3

        return HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(prominentButtonTint)
                    .frame(width: 7, height: 7)
                    .scaleEffect(index == phase ? 1.0 : 0.72)
                    .opacity(index == phase ? 1.0 : 0.28)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(prominentButtonTint.opacity(isDark ? 0.16 : 0.12))
        )
    }

    func liveIndicatorDot(size: CGFloat) -> some View {
        Image(systemName: "circle.fill")
            .font(.system(size: size, design: .rounded))
            .foregroundStyle(queueActionTint)
            .symbolEffect(.pulse, isActive: model.isBusy && !reduceMotion)
            .accessibilityHidden(true)
    }

    /// Показатель: число табличными цифрами и подпись, без плитки и значка. Цифры перекатываются при изменении.
    func figure(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.saveMe(.heading, .semibold))
                .monospacedDigit()
                .foregroundStyle(tint ?? primaryText)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: value)
            Text(title)
                .font(.saveMe(.label))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Строка списка внутри панели: разделитель вместо отдельной плитки.
    func listRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider() }
    }

    func statPill(title: String, value: Int, accent: Color) -> some View {
        figure(title, "\(value)")
    }


    func queueSummaryPill(title: String, value: String, tint: Color) -> some View {
        figure(title, value)
    }

    func settingsCard<Content: View>(_ title: String, symbol: String? = nil, padding: CGFloat = SaveMeMetrics.cardPadding, @ViewBuilder content: () -> Content) -> some View {
        card(title, symbol: symbol, padding: padding, content: content)
    }

    /// Заголовок панели: значок раздела в фирменном цвете и название.
    func cardHeader(_ title: String, symbol: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.saveMe(.title, .medium))
                    .foregroundStyle(brandTint)
                    .frame(width: 20, alignment: .center)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.saveMe(.title, .semibold))
                .foregroundStyle(primaryText)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Основная панель раздела из Liquid Glass.
    func card<Content: View>(
        _ title: String,
        symbol: String? = nil,
        padding: CGFloat = SaveMeMetrics.cardPadding,
        minHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(title, symbol: symbol)
                .padding(.horizontal, SaveMeMetrics.cardPadding)
                .padding(.top, SaveMeMetrics.cardPadding)

            content()
                .padding(.horizontal, padding)
                .padding(.bottom, padding == 0 ? SaveMeMetrics.cardPadding : padding)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .saveMeGlassSurface(cornerRadius: cardCornerRadius)
    }

    func button(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        tint: Color? = nil,
        allowWhileBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .fontWeight(prominent ? .semibold : .medium)
            .frame(maxWidth: .infinity)
        }
        .saveMeGlassButton(prominent: prominent, tint: tint.map { $0.opacity(prominent ? 1 : 0.5) })
        .controlSize(.large)
        .disabled(!allowWhileBusy && model.isBusy)
    }

    func horizontalMonospaceField(_ text: String, fontSize: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(text)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(fieldBackground)
    }

    func textEditorCard(text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .accessibilityLabel(placeholder)
                .font(.saveMe(.body, .medium, mono: true))
                .scrollContentBackground(.hidden)
                .foregroundStyle(primaryText)
                .padding(10)
                .background(Color.clear)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.saveMe(.body, .medium, mono: true))
                    .foregroundStyle(tertiaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
        .background(fieldBackground)
    }

    /// Строка очереди: значок состояния, профиль и одна строка пояснения.
    func batchQueueItem(_ item: AppModel.BatchProfileItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                if item.status == .running {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                } else {
                    Image(systemName: statusSystemImage(for: item.status))
                        .font(.saveMe(.body, .semibold))
                        .foregroundStyle(statusColor(for: item.status))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, options: .nonRepeating, value: item.status == .completed)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url)
                    .font(.saveMe(.body, .medium, mono: true))
                    .foregroundStyle(primaryText)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.message)
                    .font(.saveMe(.label))
                    .foregroundStyle(item.status == .failed ? SaveMePalette.danger : secondaryText)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 8)

            if !model.isBusy {
                Button {
                    model.removeBatchProfile(id: item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.saveMe(.micro, .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Убрать {0}", item.url))
                .accessibilityLabel(L("Убрать {0}", item.url))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityValue(item.status.title)
        .overlay(alignment: .bottom) {
            // У скачиваемого профиля разделитель превращается в бегущую полосу.
            if item.status == .running {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(brandTint)
                    .transition(.opacity)
            } else {
                Divider()
            }
        }
    }

    func statusBadge(for status: AppModel.BatchProfileItem.Status) -> some View {
        Text(status.title)
            .font(.saveMe(.micro, .bold))
            .foregroundStyle(statusColor(for: status))
            .contentTransition(.opacity)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(statusColor(for: status).opacity(isDark ? 0.14 : 0.10))
            )
    }

    func statusSystemImage(for status: AppModel.BatchProfileItem.Status) -> String {
        switch status {
        case .pending:
            return "clock"
        case .running:
            return "arrow.down.circle"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .stopped:
            return "pause.circle"
        }
    }

    func statusColor(for status: AppModel.BatchProfileItem.Status) -> Color {
        switch status {
        case .pending:
            return SaveMePalette.warning.opacity(0.80)
        case .running:
            return SaveMePalette.info.opacity(0.84)
        case .completed:
            return SaveMePalette.success.opacity(0.84)
        case .failed:
            return SaveMePalette.danger.opacity(0.80)
        case .stopped:
            return SaveMePalette.neutral.opacity(0.78)
        }
    }


    /// Подпись и значение без собственной плитки.
    func statusInlineNote(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.saveMe(.label))
                .foregroundStyle(secondaryText)

            Text(message)
                .font(.saveMe(.body, .medium))
                .foregroundStyle(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var fieldBackground: some View {
        RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
            .fill(inputFill)
            .overlay {
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: 1)
            }
    }

    var windowBackground: some View { SaveMeBackdrop() }

}

private struct ConfettiOverlayView: View {
    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let size: CGFloat
        let delay: Double
        let duration: Double
        let rotation: Double
        let color: Color
    }

    @State var animate = false

    private let particles: [Particle] = (0..<34).map { index in
        let palette: [Color] = [
            Color(red: 0.97, green: 0.31, blue: 0.38),
            Color(red: 0.13, green: 0.72, blue: 0.92),
            Color(red: 1.00, green: 0.78, blue: 0.18),
            Color(red: 0.37, green: 0.86, blue: 0.44),
            Color(red: 0.79, green: 0.41, blue: 0.95),
        ]
        return Particle(
            id: index,
            x: CGFloat((index * 29) % 100) / 100,
            size: CGFloat(8 + (index % 6) * 3),
            delay: Double(index % 8) * 0.03,
            duration: 1.9 + Double(index % 5) * 0.18,
            rotation: Double((index * 37) % 240) - 120,
            color: palette[index % palette.count]
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(particles) { particle in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size * 0.68)
                        .rotationEffect(.degrees(animate ? particle.rotation * 2.4 : particle.rotation))
                        .position(
                            x: proxy.size.width * (0.08 + particle.x * 0.84),
                            y: animate ? proxy.size.height + 40 : -40
                        )
                        .opacity(animate ? 0.0 : 1.0)
                        .animation(
                            .interpolatingSpring(stiffness: 70, damping: 11)
                                .delay(particle.delay)
                                .speed(1 / particle.duration),
                            value: animate
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                animate = false
                DispatchQueue.main.async {
                    animate = true
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Переключатель языка интерфейса (русский / English). Применяется после перезапуска приложения.
private struct LanguageSetting: View {
    @AppStorage(Localizer.languageKey) private var language = "ru"
    let secondaryText: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Language / Язык", selection: $language) {
                Text(verbatim: "Русский").tag("ru")
                Text(verbatim: "English").tag("en")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(L("Язык изменится после перезапуска приложения."))
                .font(.saveMe(.label, .medium))
                .foregroundStyle(secondaryText)
        }
    }
}
