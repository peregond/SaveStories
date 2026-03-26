import SwiftUI

struct ContentView: View {
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

    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false
    @State private var selectedSection: AppSection = .main
    @State private var showingConfetti = false
    @State private var showingAllRecentLists = false

    private var isDark: Bool { colorScheme == .dark }

    private let sidebarWidth: CGFloat = 296
    private let cardCornerRadius: CGFloat = 26
    private let controlCornerRadius: CGFloat = 18
    private let itemCornerRadius: CGFloat = 20
    private let innerCornerRadius: CGFloat = 16
    private let topContentInset: CGFloat = 30
    private let homeSummaryCardHeight: CGFloat = 208

    private func isCompactHomeLayout(for width: CGFloat) -> Bool {
        width < 760
    }

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
    private var queueActionTint: Color {
        isDark ? Color(red: 0.29, green: 0.50, blue: 0.40) : Color(red: 0.34, green: 0.58, blue: 0.46)
    }
    private var cardStroke: Color {
        isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.38)
    }

    private var versionLabel: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildVersion))"
    }

    var body: some View {
        ZStack {
            windowBackground

            HStack(spacing: 0) {
                sidebar
                detailContent
            }

            if showingConfetti {
                ConfettiOverlayView()
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(4)
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
        .onChange(of: model.celebrationToken) { _, newValue in
            guard newValue > 0 else { return }
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SaveStories")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                Text("STORIES DOWNLOADER")
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

                updatesCard
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
            case .main:
                homeTwoView
            case .batch:
                batchView
            case .reels:
                reelsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, topContentInset)
    }

    private var homeTwoView: some View {
        GeometryReader { proxy in
            let compact = isCompactHomeLayout(for: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    homeTwoHero(compact: compact)

                    if compact {
                        VStack(alignment: .leading, spacing: 20) {
                            homeStatusCard
                                .frame(maxWidth: .infinity, minHeight: homeSummaryCardHeight, alignment: .topLeading)
                            homeResultCard
                                .frame(maxWidth: .infinity, minHeight: homeSummaryCardHeight, alignment: .topLeading)
                            homeTwoComposerCard(compact: true)
                            recentListsCard(compact: true)
                            logsCard(maxHeight: 320)
                            homeTwoQueueCard(compact: true)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            homeStatusCard
                                .frame(maxWidth: .infinity, minHeight: homeSummaryCardHeight, alignment: .topLeading)
                            homeResultCard
                                .frame(maxWidth: .infinity, minHeight: homeSummaryCardHeight, alignment: .topLeading)
                        }

                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 20) {
                                homeTwoComposerCard(compact: false)
                                homeTwoQueueCard(compact: false)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)

                            VStack(alignment: .leading, spacing: 20) {
                                recentListsCard(compact: false)
                                logsCard(maxHeight: 320)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .padding(.top, 4)
            }
        }
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
                    mediaFilterCard
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)

            activityPanel
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private var reelsView: some View {
        HStack(spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHero(
                        eyebrow: "Reels",
                        title: "Выгрузка Reels появится позже",
                        subtitle: "Здесь появится отдельный сценарий для выгрузки Reels. Пока это плейсхолдер под следующий этап развития приложения."
                    )

                    card("Что планируется") {
                        VStack(alignment: .leading, spacing: 12) {
                            statusInlineNote(
                                title: "На следующем этапе",
                                message: "Добавим вставку ссылок на Reels, пакетную очередь, сохранение недавних наборов и отдельный прогресс именно под формат Reels."
                            )

                            statusInlineNote(
                                title: "Что уже можно",
                                message: "Для выгрузки актуальных stories продолжай использовать Главную и Списочную."
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)

            activityPanel
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private func homeTwoHero(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 14) {
                        homeHeroTitleBlock
                        homeHeroVersionBlock
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        homeHeroTitleBlock

                        Spacer(minLength: 0)

                        homeHeroVersionBlock
                    }
                }
            }
        }
    }

    private var homeHeroTitleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Главная")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)

            Text("Собери очередь, быстро проверь состояние выгрузки и при необходимости вернись к последнему сохранённому набору без переключений между экранами.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var homeHeroVersionBlock: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Версия")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)

            Text(versionLabel)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tertiaryText)

            if model.batchIsRunning {
                liveStatusBadge
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var homeStatusCard: some View {
        card("Status") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if model.isBusy {
                        liveIndicatorDot(size: 12)
                    } else {
                        Circle()
                            .fill(Color.green.opacity(0.78))
                            .frame(width: 12, height: 12)
                    }

                    Text(model.statusTitle)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)
                }

                Text(model.statusDetail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                stepTracker
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var homeResultCard: some View {
        card("Result") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    statPill(title: "Найдено", value: model.foundStoriesCount, accent: Color.orange.opacity(0.78))
                    statPill(title: "Сохранено", value: model.savedStoriesCount, accent: Color.green.opacity(0.78))
                }

                HStack(spacing: 12) {
                    statPill(title: "Файлов", value: model.liveDownloadedFileCount, accent: Color.blue.opacity(0.78))
                    statPill(title: "Папок", value: model.liveCreatedFolderCount, accent: Color.mint.opacity(0.78))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusRail: some View {
        HStack(spacing: 12) {
            statusRailPill(
                title: "Состояние",
                value: model.statusTitle,
                detail: model.statusDetail,
                tint: model.isBusy ? prominentButtonTint : Color.green.opacity(0.75)
            )

            statusRailPill(
                title: "Текущий шаг",
                value: model.currentStepLabel,
                detail: model.batchIsRunning ? "Сейчас \(max(model.batchCurrentIndex, 1)) из \(max(model.batchTotalCount, 1))" : "Готово к следующей выгрузке",
                tint: Color.orange.opacity(0.75)
            )

            statusRailPill(
                title: "Результат",
                value: "\(model.savedStoriesCount) сохранено",
                detail: "\(model.foundStoriesCount) найдено",
                tint: Color.blue.opacity(0.72)
            )

            statusRailPill(
                title: "В выбранной папке",
                value: "\(model.liveDownloadedFileCount) файлов",
                detail: "\(model.liveCreatedFolderCount) папок создано",
                tint: Color.mint.opacity(0.72)
            )
        }
    }

    private func homeTwoComposerCard(compact: Bool) -> some View {
        card("Fast Start") {
            VStack(alignment: .leading, spacing: 14) {
                textEditorCard(
                    text: $model.batchInput,
                    placeholder: "По одной ссылке или username на строку.\nНапример:\ndian.vegas1\nhttps://www.instagram.com/stevensetu/\nleftlanepapi"
                )
                .frame(height: 190)

                if compact {
                    VStack(spacing: 10) {
                        button("Добавить", systemImage: "plus") {
                            model.addBatchProfiles()
                        }

                        button("Запомнить", systemImage: "bookmark") {
                            model.rememberCurrentBatchList()
                        }
                        .disabled(model.batchQueue.isEmpty)

                        button("Очистить", systemImage: "xmark") {
                            model.batchInput = ""
                        }
                    }

                    VStack(spacing: 10) {
                        button("Скачать", systemImage: "play.fill", prominent: true, tint: queueActionTint) {
                            Task { await model.runBatchDownloads() }
                        }
                        .disabled(model.batchQueue.isEmpty || model.isBusy)

                        button("Остановить", systemImage: "stop.fill", allowWhileBusy: true) {
                            model.stopBatchDownloads()
                        }
                        .disabled(!model.batchIsRunning)
                    }
                } else {
                    HStack(spacing: 10) {
                        button("Добавить", systemImage: "plus") {
                            model.addBatchProfiles()
                        }

                        button("Запомнить", systemImage: "bookmark") {
                            model.rememberCurrentBatchList()
                        }
                        .disabled(model.batchQueue.isEmpty)

                        button("Очистить", systemImage: "xmark") {
                            model.batchInput = ""
                        }
                    }

                    HStack(spacing: 10) {
                        button("Скачать", systemImage: "play.fill", prominent: true, tint: queueActionTint) {
                            Task { await model.runBatchDownloads() }
                        }
                        .disabled(model.batchQueue.isEmpty || model.isBusy)

                        button("Остановить", systemImage: "stop.fill", allowWhileBusy: true) {
                            model.stopBatchDownloads()
                        }
                        .disabled(!model.batchIsRunning)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    downloadModePicker
                    mediaSelectionPicker
                }

                Group {
                    if compact {
                        VStack(alignment: .leading, spacing: 14) {
                            destinationInlineCard(compact: true)
                            statusInlineNote(
                                title: "Быстрый сценарий",
                                message: "Слева вставляешь профили, справа выбираешь режим и папку, затем запускаешь очередь одной кнопкой."
                            )
                        }
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            destinationInlineCard(compact: false)

                            statusInlineNote(
                                title: "Быстрый сценарий",
                                message: "Слева вставляешь профили, справа выбираешь режим и папку, затем запускаешь очередь одной кнопкой."
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }

            }
        }
    }

    private func homeTwoQueueCard(compact: Bool) -> some View {
        card("Очередь") {
            VStack(alignment: .leading, spacing: 14) {
                if compact {
                    VStack(spacing: 10) {
                        queueSummaryPill(
                            title: "В очереди",
                            value: "\(model.batchQueue.count)",
                            tint: Color.white.opacity(isDark ? 0.10 : 0.62)
                        )
                        queueSummaryPill(
                            title: "Недавних наборов",
                            value: "\(model.recentBatchLists.count)",
                            tint: Color.white.opacity(isDark ? 0.10 : 0.62)
                        )
                        queueSummaryPill(
                            title: "Режим",
                            value: model.downloadMode.title,
                            tint: prominentButtonTint.opacity(isDark ? 0.20 : 0.14)
                        )
                    }
                } else {
                    HStack(spacing: 10) {
                        queueSummaryPill(
                            title: "В очереди",
                            value: "\(model.batchQueue.count)",
                            tint: Color.white.opacity(isDark ? 0.10 : 0.62)
                        )
                        queueSummaryPill(
                            title: "Недавних наборов",
                            value: "\(model.recentBatchLists.count)",
                            tint: Color.white.opacity(isDark ? 0.10 : 0.62)
                        )
                        queueSummaryPill(
                            title: "Режим",
                            value: model.downloadMode.title,
                            tint: prominentButtonTint.opacity(isDark ? 0.20 : 0.14)
                        )
                    }
                }

                if model.batchQueue.isEmpty {
                    Text("Список пока пустой. Добавь профили сверху или выбери один из недавних наборов справа.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryText)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                                .fill(itemFill)
                        )
                } else {
                    if model.batchTotalCount > 0 {
                        batchProgressStripe
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.batchQueue) { item in
                                batchQueueItem(item)
                            }
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 340)
                }

                if compact {
                    VStack(alignment: .leading, spacing: 10) {
                        button("Очистить очередь", systemImage: "trash") {
                            model.clearBatchQueue()
                        }
                        .disabled(model.batchQueue.isEmpty || model.isBusy)

                        Text("После запуска текущий список появится в блоке «Недавние наборы».")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(tertiaryText)
                    }
                } else {
                    HStack(spacing: 10) {
                        button("Очистить очередь", systemImage: "trash") {
                            model.clearBatchQueue()
                        }
                        .disabled(model.batchQueue.isEmpty || model.isBusy)

                        Spacer(minLength: 0)

                        Text("После запуска текущий список появится в блоке «Недавние наборы».")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(tertiaryText)
                    }
                }
            }
        }
    }

    private func recentListsCard(compact: Bool) -> some View {
        card("Недавнее") {
            VStack(alignment: .leading, spacing: 12) {
                if model.recentBatchLists.isEmpty {
                    Text("Здесь будут появляться сохранённые и недавно запущенные списки профилей.")
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
                    ZStack(alignment: .topLeading) {
                        if !showingAllRecentLists && model.recentBatchLists.count > 1 {
                            RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                                .fill(itemFill.opacity(0.68))
                                .frame(height: 132)
                                .offset(x: 8, y: 8)

                            RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                                .fill(itemFill.opacity(0.82))
                                .frame(height: 132)
                                .offset(x: 4, y: 4)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(displayedRecentBatchLists) { list in
                                recentListCard(list, compact: compact)
                            }
                        }
                    }
                    .padding(.bottom, !showingAllRecentLists && model.recentBatchLists.count > 1 ? 10 : 0)

                    if model.recentBatchLists.count > 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingAllRecentLists.toggle()
                            }
                        } label: {
                            Text(showingAllRecentLists ? "свернуть" : "ещё")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.black.opacity(isDark ? 0.72 : 0.86))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var displayedRecentBatchLists: [AppModel.RecentBatchList] {
        showingAllRecentLists ? model.recentBatchLists : Array(model.recentBatchLists.prefix(1))
    }

    private func recentListCard(_ list: AppModel.RecentBatchList, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)

                    Text(list.subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .foregroundStyle(tertiaryText)
                }

                Spacer(minLength: 0)

                Button {
                    model.removeRecentBatchList(id: list.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(isDark ? 0.06 : 0.42)))
                }
                .buttonStyle(.plain)
            }

            Text(list.urls.prefix(3).joined(separator: "\n"))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)

            if compact {
                VStack(spacing: 8) {
                    button("Добавить", systemImage: "plus") {
                        model.applyRecentBatchList(list)
                    }

                    button("Заменить", systemImage: "arrow.triangle.swap") {
                        model.replaceQueueWithRecentBatchList(list)
                    }
                    .disabled(model.isBusy)
                }
            } else {
                HStack(spacing: 8) {
                    button("Добавить", systemImage: "plus") {
                        model.applyRecentBatchList(list)
                    }

                    button("Заменить", systemImage: "arrow.triangle.swap") {
                        model.replaceQueueWithRecentBatchList(list)
                    }
                    .disabled(model.isBusy)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                .fill(itemFill)
        )
    }

    private func destinationInlineCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Папка сохранения")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(tertiaryText)

            horizontalMonospaceField(model.saveDirectory.path, fontSize: 12)
                .frame(height: 52)

            if compact {
                VStack(spacing: 8) {
                    button("Выбрать", systemImage: "folder") {
                        model.chooseSaveDirectory()
                    }

                    button("Показать", systemImage: "arrow.up.forward.app") {
                        model.openSaveDirectory()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    button("Выбрать", systemImage: "folder") {
                        model.chooseSaveDirectory()
                    }

                    button("Показать", systemImage: "arrow.up.forward.app") {
                        model.openSaveDirectory()
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                .fill(itemFill)
        )
    }

    private var batchProgressStripe: some View {
        HStack(alignment: .center, spacing: 12) {
            liveIndicatorDot(size: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("Сейчас \(model.batchCurrentIndex) из \(model.batchTotalCount), осталось \(model.batchRemainingCount)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                if !model.batchCurrentURL.isEmpty {
                    Text(model.batchCurrentURL)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(prominentButtonTint.opacity(isDark ? 0.22 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .strokeBorder(prominentButtonTint.opacity(isDark ? 0.35 : 0.18), lineWidth: 1)
        )
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            activityHeader
            downloadsCard
            logsCard()
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

                HStack(spacing: 12) {
                    statPill(title: "Файлов загружено", value: model.liveDownloadedFileCount, accent: Color.blue.opacity(0.78))
                    statPill(title: "Папок создано", value: model.liveCreatedFolderCount, accent: Color.mint.opacity(0.78))
                }

                Text("Счётчики считаются по содержимому выбранной папки сохранения.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(quaternaryText)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var mediaFilterCard: some View {
        card("Что сохранять") {
            mediaSelectionPicker
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

    private func logsCard(maxHeight: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Логи")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(quaternaryText)

                Spacer(minLength: 0)

                Button {
                    model.copyLogs()
                } label: {
                    Label("Скопировать логи", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

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
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: maxHeight ?? .infinity, alignment: .topLeading)
        }
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
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

    private var updatesCard: some View {
        card("Обновления") {
            VStack(alignment: .leading, spacing: 12) {
                statusInlineNote(
                    title: "Автообновление",
                    message: model.updateSummary
                )

                button("Проверить обновления", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.checkForUpdates() }
                }
                .disabled(!model.canCheckForUpdates)
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

    private var mediaSelectionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Что сохранять")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(tertiaryText)

            Picker("Что сохранять", selection: $model.mediaSelectionMode) {
                ForEach(AppModel.MediaSelectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(model.mediaSelectionMode.detail)
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
            ZStack {
                Circle()
                    .fill(model.isBusy ? prominentButtonTint.opacity(isDark ? 0.24 : 0.14) : Color.clear)
                    .frame(width: 30, height: 30)
                    .scaleEffect(model.isBusy ? 1.0 : 0.88)
                    .opacity(model.isBusy ? 1 : 0)

                Image(systemName: model.isBusy ? "point.3.connected.trianglepath.dotted" : "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.isBusy ? prominentButtonTint : tertiaryText)
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: model.isBusy)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Текущий шаг")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(quaternaryText)

                if model.isBusy {
                    TimelineView(.periodic(from: .now, by: 0.6)) { context in
                        Text(animatedBusyStepLabel(at: context.date))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(model.currentStepLabel)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if model.isBusy {
                TimelineView(.periodic(from: .now, by: 0.24)) { context in
                    busyStepActivityIndicator(at: context.date)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(model.isBusy ? prominentButtonTint.opacity(isDark ? 0.18 : 0.10) : itemFill)
        )
    }

    private func animatedBusyStepLabel(at date: Date) -> String {
        let base = model.currentStepLabel.isEmpty ? "Идёт подготовка выгрузки" : model.currentStepLabel
        let phase = Int(date.timeIntervalSinceReferenceDate / 0.6) % 4
        return base + String(repeating: ".", count: phase)
    }

    private func busyStepActivityIndicator(at date: Date) -> some View {
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

    private func liveIndicatorDot(size: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 4.8) + 1) / 2
            let glowScale = 0.72 + (phase * 0.58)
            let glowOpacity = 0.16 + (phase * 0.88)
            let glowBlur = 0.4 + (phase * 3.8)
            let coreScale = 0.80 + (phase * 0.34)
            let coreOpacity = 0.52 + (phase * 0.48)
            let shadowRadius = 3 + (phase * 18)

            ZStack {
                Circle()
                    .fill(Color.green.opacity(isDark ? 0.44 : 0.34))
                    .frame(width: size * 3.1, height: size * 3.1)
                    .scaleEffect(glowScale)
                    .opacity(glowOpacity)
                    .blur(radius: glowBlur)

                Circle()
                    .fill(Color.green.opacity(1.0))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isDark ? 0.30 : 0.62), lineWidth: 1)
                    )
                    .scaleEffect(coreScale)
                    .opacity(coreOpacity)
                    .shadow(color: Color.green.opacity(isDark ? 0.88 : 0.64), radius: shadowRadius)
            }
        }
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

    private func statusRailPill(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(quaternaryText)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)
                .lineLimit(2)

            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                        .fill(tint.opacity(isDark ? 0.16 : 0.10))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
    }

    private func queueSummaryPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(tertiaryText)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(tint)
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
        tint: Color? = nil,
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
        .tint(tint ?? (prominent ? prominentButtonTint : secondaryButtonTint))
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

    @State private var animate = false

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
