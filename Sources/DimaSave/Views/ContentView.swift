import SwiftUI

struct ContentView: View {
    enum AppSection: String, CaseIterable, Identifiable {
        case batch
        case home

        var id: String { rawValue }

        var title: String {
            switch self {
            case .batch:
                "Списочная"
            case .home:
                "Главная"
            }
        }

        var subtitle: String {
            switch self {
            case .batch:
                "Очередь профилей"
            case .home:
                "Текущий режим выгрузки"
            }
        }

        var systemImage: String {
            switch self {
            case .batch:
                "list.bullet.rectangle.portrait"
            case .home:
                "sparkles.rectangle.stack"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false
    @State private var selectedSection: AppSection = .batch
    @State private var busyPulse = false

    private var isDark: Bool { colorScheme == .dark }

    private let sidebarWidth: CGFloat = 272
    private let cardCornerRadius: CGFloat = 26
    private let controlCornerRadius: CGFloat = 18
    private let itemCornerRadius: CGFloat = 20
    private let innerCornerRadius: CGFloat = 16
    private let topContentInset: CGFloat = 30

    private var backgroundGradient: [Color] {
        if isDark {
            return [
                Color(red: 0.07, green: 0.09, blue: 0.12),
                Color(red: 0.09, green: 0.12, blue: 0.16),
                Color(red: 0.08, green: 0.11, blue: 0.13),
            ]
        }

        return [
            Color(red: 0.96, green: 0.94, blue: 0.89),
            Color(red: 0.90, green: 0.94, blue: 0.98),
            Color(red: 0.88, green: 0.93, blue: 0.92),
        ]
    }

    private var glassTint: Color {
        isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.38)
    }

    private var primaryText: Color { isDark ? Color.white.opacity(0.94) : Color.black.opacity(0.84) }
    private var secondaryText: Color { isDark ? Color.white.opacity(0.74) : Color.black.opacity(0.60) }
    private var tertiaryText: Color { isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.48) }
    private var quaternaryText: Color { isDark ? Color.white.opacity(0.44) : Color.black.opacity(0.55) }
    private var cardFill: Color { isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.26) }
    private var inputFill: Color { isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.62) }
    private var pillFill: Color { isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.54) }
    private var itemFill: Color { isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.60) }
    private var settingsIconColor: Color { isDark ? Color.white.opacity(0.84) : Color.black.opacity(0.76) }
    private var secondaryButtonTint: Color { isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.66) }
    private var prominentButtonTint: Color {
        isDark ? Color(red: 0.18, green: 0.45, blue: 0.62) : Color(red: 0.12, green: 0.37, blue: 0.52)
    }
    private var cardStroke: Color {
        isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.38)
    }

    private var versionLabel: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "Версия \(shortVersion) (\(buildVersion))"
    }

    var body: some View {
        ZStack {
            windowBackground

            HStack(spacing: 0) {
                sidebar
                detailContent
            }
        }
        .alert("Нужен вход в Instagram", isPresented: $model.showLoginPrompt) {
            Button("Не сейчас", role: .cancel) {
                model.dismissLoginPrompt()
            }
            Button("Открыть браузер") {
                Task { await model.login() }
            }
        } message: {
            Text("Для первой выгрузки stories войди в Instagram через браузер приложения. Окно останется открытым, пока вход не будет завершён.")
        }
        .onAppear {
            guard !busyPulse else { return }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                busyPulse = true
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SaveStories")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                Text("Stories downloader")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(tertiaryText)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 18)

            VStack(spacing: 10) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        sidebarRow(for: section)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)

            settingsSidebarButton
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .frame(minWidth: sidebarWidth, idealWidth: sidebarWidth, maxWidth: sidebarWidth)
        .padding(.top, topContentInset)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(isDark ? 0.05 : 0.35))
                .frame(width: 1)
        }
    }

    private func sidebarRow(for section: AppSection) -> some View {
        let isSelected = selectedSection == section

        return HStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isSelected ? prominentButtonTint.opacity(0.85) : Color.white.opacity(isDark ? 0.06 : 0.42))
                )
                .foregroundStyle(isSelected ? Color.white : primaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                Text(section.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelected ? prominentButtonTint.opacity(isDark ? 0.18 : 0.14) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.white.opacity(isDark ? 0.08 : 0.34) : Color.clear, lineWidth: 1)
        )
    }

    private var settingsSidebarButton: some View {
        Button {
            showingSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Настройки")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Воркер, сессия и среда")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                Spacer()
            }
            .foregroundStyle(settingsIconColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(glassTint)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            settingsPopover
        }
    }

    private var settingsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Служебные настройки")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                statusCards
                runtimeCard
                sessionCard
            }
            .padding(20)
        }
        .frame(width: 520, height: 460)
        .background(windowBackground)
    }

    private var detailContent: some View {
        Group {
            switch selectedSection {
            case .batch:
                batchView
            case .home:
                homeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, topContentInset)
    }

    private var homeView: some View {
        HStack(spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(
                        title: "SaveStories",
                        subtitle: "macOS-приложение для выгрузки активных stories из Instagram по ссылке на профиль."
                    )
                    progressCard
                    destinationCard
                    profileCard
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)

            activityPanel
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private var batchView: some View {
        HStack(spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHero(
                        eyebrow: "Списочная выгрузка",
                        title: "Пакетная очередь профилей",
                        subtitle: "Добавь сразу несколько ссылок или usernames. Приложение последовательно выгрузит stories для каждого профиля."
                    )
                    batchInputCard
                    batchQueueCard
                    destinationCard
                    batchModeCard
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)

            activityPanel
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            activityHeader
            downloadsCard
            logsCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)

            Text(subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(versionLabel)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tertiaryText)
        }
    }

    private func detailHero(eyebrow: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(tertiaryText)

            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)

            Text(subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusCards: some View {
        HStack(spacing: 12) {
            statusCard(
                title: "Воркер",
                message: model.workerSummary,
                accent: model.workerReady ? Color.green.opacity(0.78) : Color.orange.opacity(0.78)
            )

            statusCard(
                title: "Сессия",
                message: model.sessionSummary,
                accent: model.sessionReady ? Color.blue.opacity(0.78) : Color.gray.opacity(0.65)
            )
        }
    }

    private var progressCard: some View {
        card("Статус загрузки") {
            VStack(alignment: .leading, spacing: 12) {
                if model.isBusy {
                    liveStatusBadge
                }

                HStack(spacing: 12) {
                    if model.isBusy {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green.opacity(0.78))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.statusTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryText)

                        Text(model.statusDetail)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                stepTracker
                    .opacity(model.isBusy ? 1 : 0.82)

                HStack(spacing: 12) {
                    statPill(title: "Найдено", value: model.foundStoriesCount, accent: Color.orange.opacity(0.78))
                    statPill(title: "Сохранено", value: model.savedStoriesCount, accent: Color.green.opacity(0.78))
                }
            }
        }
    }

    private var destinationCard: some View {
        card("Папка сохранения") {
            VStack(alignment: .leading, spacing: 12) {
                horizontalMonospaceField(model.saveDirectory.path, fontSize: 13)

                HStack(spacing: 10) {
                    button("Выбрать папку", systemImage: "folder") {
                        model.chooseSaveDirectory()
                    }

                    button("Показать", systemImage: "arrow.up.forward.app") {
                        model.openSaveDirectory()
                    }
                }
            }
        }
    }

    private var profileCard: some View {
        card("Ссылка на профиль") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("https://www.instagram.com/username/", text: $model.profileURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .padding(12)
                    .background(fieldBackground)

                downloadModePicker

                button("Скачать активные stories", systemImage: "photo.stack.fill", prominent: true) {
                    Task { await model.downloadProfileStories() }
                }
            }
        }
    }

    private var batchInputCard: some View {
        card("Добавить профили") {
            VStack(alignment: .leading, spacing: 12) {
                textEditorCard(
                    text: $model.batchInput,
                    placeholder: "Вставь по одной ссылке или username на строку.\nНапример:\nhttps://www.instagram.com/dian.vegas1/\nmonetentony"
                )
                .frame(height: 144)

                HStack(spacing: 10) {
                    button("Добавить в очередь", systemImage: "plus") {
                        model.addBatchProfiles()
                    }

                    button("Очистить поле", systemImage: "xmark") {
                        model.batchInput = ""
                    }
                }
            }
        }
    }

    private var batchQueueCard: some View {
        card("Очередь профилей") {
            VStack(alignment: .leading, spacing: 12) {
                if model.batchTotalCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Сейчас \(model.batchCurrentIndex) из \(model.batchTotalCount), осталось \(model.batchRemainingCount)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryText)

                        if !model.batchCurrentURL.isEmpty {
                            Text(model.batchCurrentURL)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(secondaryText)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                            .fill(itemFill)
                    )
                }

                if model.batchQueue.isEmpty {
                    Text("Очередь пока пустая. Добавь несколько профилей, и приложение обработает их по одному.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                                .fill(itemFill)
                        )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.batchQueue) { item in
                                batchQueueItem(item)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }

                HStack(spacing: 10) {
                    button("Скачать очередь", systemImage: "square.stack.3d.down.forward.fill", prominent: true) {
                        Task { await model.runBatchDownloads() }
                    }
                    .disabled(model.batchQueue.isEmpty || model.isBusy)

                    button("Остановить", systemImage: "stop.fill", allowWhileBusy: true) {
                        model.stopBatchDownloads()
                    }
                    .disabled(!model.batchIsRunning)

                    button("Очистить очередь", systemImage: "trash") {
                        model.clearBatchQueue()
                    }
                    .disabled(model.batchQueue.isEmpty || model.isBusy)
                }
            }
        }
    }

    private var batchModeCard: some View {
        card("Режим выгрузки") {
            VStack(alignment: .leading, spacing: 12) {
                downloadModePicker

                Text("Этот режим использует общую сессию Instagram и прогоняет список профилей строго по очереди.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var activityHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Активность")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                if model.isBusy {
                    liveIndicatorDot(size: 10)
                }
            }

            Text(model.lastResult)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if model.isBusy || !model.currentStepLabel.isEmpty {
                HStack(spacing: 8) {
                    if model.isBusy {
                        liveIndicatorDot(size: 8)
                    }

                    Text(model.currentStepLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var downloadsCard: some View {
        card("Последние загрузки", padding: 0) {
            Group {
                if model.downloadedItems.isEmpty {
                    Text("Пока нет сохранённых файлов.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.downloadedItems.prefix(20)) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.mediaType.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(tertiaryText)

                                    Text(item.localPath)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(primaryText)
                                        .textSelection(.enabled)

                                    Text(item.metadataPath)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(secondaryText)
                                        .textSelection(.enabled)

                                    Text(item.sourceURL)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(secondaryText)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                                        .fill(itemFill)
                                )
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 260, alignment: .topLeading)
        }
    }

    private var logsCard: some View {
        card("Логи", padding: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.logs, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var runtimeCard: some View {
        card("Среда") {
            VStack(alignment: .leading, spacing: 12) {
                horizontalMonospaceField(
                    model.runtimeSummary.isEmpty ? "Информация о среде появится после проверки воркера." : model.runtimeSummary,
                    fontSize: 12
                )

                button("Открыть папку среды", systemImage: "internaldrive") {
                    model.openRuntimeDirectory()
                }
            }
        }
    }

    private var sessionCard: some View {
        card("Воркер и сессия") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Если среда ещё не подготовлена, установи движок прямо отсюда. После этого можно открыть браузер для входа и проверить сессию.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                statusInlineNote(
                    title: "Авторизация",
                    message: "Браузер для входа держится открытым, пока Instagram не выдаст активную сессию или пока не истечёт таймаут."
                )

                VStack(spacing: 10) {
                    if model.hasEmbeddedRuntime {
                        statusInlineNote(
                            title: "Движок уже встроен",
                            message: "В этой release-сборке Python, Playwright и Chromium уже лежат внутри приложения. Отдельная установка не нужна."
                        )
                    } else {
                        HStack(spacing: 10) {
                            button("Установить движок", systemImage: "arrow.down.circle") {
                                Task { await model.bootstrapEnvironment() }
                            }

                            button("Проверить среду", systemImage: "bolt.horizontal.circle") {
                                Task { await model.refreshEnvironment() }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        button("Открыть браузер для входа", systemImage: "person.crop.circle.badge.checkmark") {
                            Task { await model.login() }
                        }

                        button("Проверить сессию", systemImage: "checkmark.shield") {
                            Task { await model.checkSession() }
                        }
                    }
                }
            }
        }
    }

    private var downloadModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Режим выгрузки")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(tertiaryText)

            Picker("Режим выгрузки", selection: $model.downloadMode) {
                ForEach(AppModel.DownloadMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(model.downloadMode.detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusCard(title: String, message: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)

                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(quaternaryText)
            }

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                        .fill(cardFill)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
    }

    private var liveStatusBadge: some View {
        HStack(spacing: 10) {
            liveIndicatorDot(size: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("Выгрузка выполняется")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(primaryText)

                Text("Приложение работает, просто дождись завершения текущего шага.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(prominentButtonTint.opacity(isDark ? 0.22 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .strokeBorder(prominentButtonTint.opacity(isDark ? 0.36 : 0.22), lineWidth: 1)
        )
    }

    private var stepTracker: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isBusy ? "point.3.connected.trianglepath.dotted" : "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.isBusy ? prominentButtonTint : tertiaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text("Текущий шаг")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(quaternaryText)

                Text(model.currentStepLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(itemFill)
        )
    }

    private func liveIndicatorDot(size: CGFloat) -> some View {
        Circle()
            .fill(Color.green.opacity(isDark ? 0.95 : 0.82))
            .frame(width: size, height: size)
            .scaleEffect(busyPulse ? 1.0 : 0.72)
            .opacity(busyPulse ? 1.0 : 0.42)
            .shadow(color: Color.green.opacity(isDark ? 0.55 : 0.28), radius: busyPulse ? 12 : 4)
    }

    private func statPill(title: String, value: Int, accent: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(tertiaryText)

                Text("\(value)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(pillFill)
        )
    }

    private func card<Content: View>(_ title: String, padding: CGFloat = 18, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(quaternaryText)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            content()
                .padding(.horizontal, padding)
                .padding(.bottom, padding == 0 ? 18 : padding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    private func button(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        allowWhileBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? prominentButtonTint : secondaryButtonTint)
        .disabled(!allowWhileBusy && model.isBusy)
    }

    private func horizontalMonospaceField(_ text: String, fontSize: CGFloat) -> some View {
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

    private func textEditorCard(text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .scrollContentBackground(.hidden)
                .foregroundStyle(primaryText)
                .padding(10)
                .background(Color.clear)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(tertiaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
        .background(fieldBackground)
    }

    private func batchQueueItem(_ item: AppModel.BatchProfileItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor(for: item.status))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.url)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(primaryText)
                            .textSelection(.enabled)

                        Text(item.status.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .textCase(.uppercase)
                            .foregroundStyle(tertiaryText)
                    }

                    Spacer(minLength: 8)

                    if !model.isBusy {
                        Button {
                            model.removeBatchProfile(id: item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(secondaryText)
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(isDark ? 0.06 : 0.30))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(item.message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                .fill(itemFill)
        )
    }

    private func statusColor(for status: AppModel.BatchProfileItem.Status) -> Color {
        switch status {
        case .pending:
            return Color.orange.opacity(0.80)
        case .running:
            return Color.blue.opacity(0.84)
        case .completed:
            return Color.green.opacity(0.84)
        case .failed:
            return Color.red.opacity(0.80)
        case .stopped:
            return Color.gray.opacity(0.78)
        }
    }

    private func placeholderBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(prominentButtonTint.opacity(0.82))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusInlineNote(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(tertiaryText)

            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                .fill(pillFill)
        )
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
            .fill(inputFill)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardFill)
        }
    }

    private var sidebarBackground: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
            Rectangle()
                .fill(glassTint.opacity(isDark ? 0.75 : 0.9))
        }
    }

    private var windowBackground: some View {
        ZStack {
            LinearGradient(
                colors: backgroundGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(isDark ? 0.05 : 0.20))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: -420, y: -280)

            Circle()
                .fill(prominentButtonTint.opacity(isDark ? 0.12 : 0.10))
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .offset(x: 460, y: 260)
        }
    }
}
