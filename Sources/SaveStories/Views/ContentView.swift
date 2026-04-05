import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var colorScheme
    @State var selectedSection: AppSection = .main
    @State var showingConfetti = false
    @State var showingAllRecentLists = false
    @State var showingRuntimeDetails = false
    @State var showingLogsCopiedFeedback = false

    var isDark: Bool { colorScheme == .dark }

    let sidebarWidth: CGFloat = 296
    let cardCornerRadius: CGFloat = 26
    let controlCornerRadius: CGFloat = 18
    let itemCornerRadius: CGFloat = 20
    let innerCornerRadius: CGFloat = 16
    let topContentInset: CGFloat = 30
    let homeSummaryCardHeight: CGFloat = 208

    func isCompactHomeLayout(for width: CGFloat) -> Bool {
        width < 760
    }

    var backgroundGradient: [Color] {
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

    var glassTint: Color {
        isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.38)
    }

    var primaryText: Color { isDark ? Color.white.opacity(0.94) : Color.black.opacity(0.84) }
    var secondaryText: Color { isDark ? Color.white.opacity(0.74) : Color.black.opacity(0.60) }
    var tertiaryText: Color { isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.48) }
    var quaternaryText: Color { isDark ? Color.white.opacity(0.44) : Color.black.opacity(0.55) }
    var cardFill: Color { isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.26) }
    var inputFill: Color { isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.62) }
    var pillFill: Color { isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.54) }
    var itemFill: Color { isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.60) }
    var settingsIconColor: Color { isDark ? Color.white.opacity(0.84) : Color.black.opacity(0.76) }
    var secondaryButtonTint: Color { isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.66) }
    var prominentButtonTint: Color {
        isDark ? Color(red: 0.18, green: 0.45, blue: 0.62) : Color(red: 0.12, green: 0.37, blue: 0.52)
    }
    var queueActionTint: Color {
        isDark ? Color(red: 0.29, green: 0.50, blue: 0.40) : Color(red: 0.34, green: 0.58, blue: 0.46)
    }
    var cardStroke: Color {
        isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.38)
    }

    var versionLabel: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildVersion))"
    }

    var reelsLinkCount: Int {
        model.reelsInput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    var batchProfileInputCount: Int {
        model.batchInput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    var isReelsDownloadInProgress: Bool {
        let combined = "\(model.statusTitle) \(model.currentStepLabel)".lowercased()
        return model.isBusy && combined.contains("reels")
    }

    var isStoriesDownloadInProgress: Bool {
        model.batchIsRunning || (model.isBusy && !isReelsDownloadInProgress)
    }

    var selectedDownloadModeDescription: String {
        switch model.downloadMode {
        case .background:
            return "Браузер скрыт, работает незаметно"
        case .visible:
            return "Открывается окно Chromium, можно наблюдать"
        }
    }

    var selectedMediaSelectionDescription: String {
        switch model.mediaSelectionMode {
        case .all:
            return "Скачиваются все сторис"
        case .videoOnly:
            return "Фото пропускаются"
        }
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


    func homeTwoComposerCard(compact: Bool) -> some View {
        card("Профили для скачивания") {
            VStack(alignment: .leading, spacing: 14) {
                storiesInputEditor

                if compact {
                    VStack(spacing: 10) {
                        ghostButton("Добавить", systemImage: "plus") {
                            model.addBatchProfiles()
                        }

                        ghostButton("Запомнить", systemImage: "bookmark") {
                            model.rememberCurrentBatchList()
                        }
                        .disabled(model.batchQueue.isEmpty)

                        ghostButton("Очистить", systemImage: "xmark") {
                            model.batchInput = ""
                        }
                        .disabled(model.batchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                    }

                    VStack(spacing: 10) {
                        storiesDownloadButton
                        storiesStopButton
                    }
                } else {
                    HStack(spacing: 10) {
                        ghostButton("Добавить", systemImage: "plus") {
                            model.addBatchProfiles()
                        }

                        ghostButton("Запомнить", systemImage: "bookmark") {
                            model.rememberCurrentBatchList()
                        }
                        .disabled(model.batchQueue.isEmpty)

                        ghostButton("Очистить", systemImage: "xmark") {
                            model.batchInput = ""
                        }
                        .disabled(model.batchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                    }

                    HStack(spacing: 10) {
                        storiesDownloadButton
                        storiesStopButton
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    storiesDownloadModePicker
                    storiesMediaSelectionPicker
                }

                Group {
                    if compact {
                        VStack(alignment: .leading, spacing: 14) {
                            destinationInlineCard(compact: true)
                            Text("Вставь профили, выбери режим и папку — затем нажми «Скачать».")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(quaternaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            destinationInlineCard(compact: false)

                            Text("Вставь профили, выбери режим и папку — затем нажми «Скачать».")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(quaternaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(
                                    RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                                        .fill(itemFill)
                                )
                        }
                    }
                }

            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isBusy)
    }

    func homeTwoQueueCard(compact: Bool) -> some View {
        card("Очередь") {
            VStack(alignment: .leading, spacing: 14) {
                if compact {
                    VStack(spacing: 10) {
                        queueSummaryBadge(text: "В очереди \(model.batchQueue.count)", tint: Color.white.opacity(isDark ? 0.10 : 0.62))
                        queueSummaryBadge(text: "Наборов \(model.recentBatchLists.count)", tint: Color.white.opacity(isDark ? 0.10 : 0.62))
                        queueSummaryBadge(text: "Режим: \(model.downloadMode.title)", tint: prominentButtonTint.opacity(isDark ? 0.20 : 0.14))
                    }
                } else {
                    HStack(spacing: 10) {
                        queueSummaryBadge(text: "В очереди \(model.batchQueue.count)", tint: Color.white.opacity(isDark ? 0.10 : 0.62))
                        queueSummaryBadge(text: "Наборов \(model.recentBatchLists.count)", tint: Color.white.opacity(isDark ? 0.10 : 0.62))
                        queueSummaryBadge(text: "Режим: \(model.downloadMode.title)", tint: prominentButtonTint.opacity(isDark ? 0.20 : 0.14))
                    }
                }

                if model.batchQueue.isEmpty {
                    Text("Пока пусто. Добавь профили выше или выбери недавний набор справа.")
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
                            .transition(.opacity)
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
                        ghostButton("Очистить очередь", systemImage: "trash", tint: Color.red.opacity(0.78)) {
                            model.clearBatchQueue()
                        }
                        .disabled(model.batchQueue.isEmpty || model.isBusy)

                        Text("После запуска список сохранится в «Недавних наборах».")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(quaternaryText)
                    }
                } else {
                    HStack(spacing: 10) {
                        ghostButton("Очистить очередь", systemImage: "trash", tint: Color.red.opacity(0.78)) {
                            model.clearBatchQueue()
                        }
                        .disabled(model.batchQueue.isEmpty || model.isBusy)

                        Spacer(minLength: 0)

                        Text("После запуска список сохранится в «Недавних наборах».")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(quaternaryText)
                    }
                }
            }
        }
    }

    func recentListsCard(compact: Bool) -> some View {
        card("Недавние наборы") {
            VStack(alignment: .leading, spacing: 12) {
                if model.recentBatchLists.isEmpty {
                    Text("Здесь появятся сохранённые и недавно запущенные наборы профилей.")
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

                    if model.recentBatchLists.count > 3 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingAllRecentLists.toggle()
                            }
                        } label: {
                            Text(showingAllRecentLists ? "Свернуть ↑" : "Показать ещё ↓")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(itemFill)
                                )
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)

                    HStack(spacing: 6) {
                        Text(list.subtitle)
                        Text("·")
                        Text(formattedRecentListDate(list.createdAt))
                    }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
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
                    ghostButton("Добавить в очередь", systemImage: "plus") {
                        model.applyRecentBatchList(list)
                    }

                    ghostButton("Заменить очередь", systemImage: "arrow.triangle.swap") {
                        model.replaceQueueWithRecentBatchList(list)
                    }
                    .disabled(model.isBusy)
                }
            } else {
                HStack(spacing: 8) {
                    ghostButton("Добавить в очередь", systemImage: "plus") {
                        model.applyRecentBatchList(list)
                    }

                    ghostButton("Заменить очередь", systemImage: "arrow.triangle.swap") {
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

    func destinationInlineCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Папка для сохранения")
                .font(.caption)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(tertiaryText)

            Text(model.saveDirectory.path)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))
                .frame(height: 52)

            if compact {
                VStack(spacing: 8) {
                    ghostButton("Выбрать папку", systemImage: "folder.badge.plus") {
                        model.chooseSaveDirectory()
                    }

                    ghostButton("Показать в Finder", systemImage: "folder") {
                        model.openSaveDirectory()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ghostButton("Выбрать папку", systemImage: "folder.badge.plus") {
                        model.chooseSaveDirectory()
                    }

                    ghostButton("Показать в Finder", systemImage: "folder") {
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

    var batchProgressStripe: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Скачиваю \(model.batchCurrentIndex) из \(model.batchTotalCount) — осталось \(model.batchRemainingCount)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)

            ProgressView(value: Double(model.batchCurrentIndex), total: Double(max(model.batchTotalCount, 1)))
                .progressViewStyle(.linear)
                .tint(prominentButtonTint)

            if !model.batchCurrentURL.isEmpty {
                Text(model.batchCurrentURL)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
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

    var activityPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            activityHeader
            downloadsCard
            homeLogsCard()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func header(title: String, subtitle: String) -> some View {
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

    func detailHero(eyebrow: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.caption)
                .tracking(1.3)
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

    var statusCards: some View {
        HStack(spacing: 12) {
            statusCard(title: "Воркер", presentation: workerStatusPresentation)
            statusCard(title: "Сессия", presentation: sessionStatusPresentation)
        }
    }

    var progressCard: some View {
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

    var destinationCard: some View {
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

    var profileCard: some View {
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

    var batchInputCard: some View {
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

    var batchQueueCard: some View {
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

    var batchModeCard: some View {
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

    var mediaFilterCard: some View {
        card("Что сохранять") {
            mediaSelectionPicker
        }
    }

    var activityHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Состояние")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                homeStatusBadge
                    .transition(.opacity)
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

    var homeStatusBadge: some View {
        let isError = model.statusTitle.lowercased().contains("ошиб")
        let isDone = model.statusTitle.lowercased().contains("готов")
        let title: String
        let tint: Color

        if isStoriesDownloadInProgress {
            title = "Идёт загрузка"
            tint = Color.blue.opacity(0.82)
        } else if isError {
            title = "Ошибка"
            tint = Color.red.opacity(0.82)
        } else if isDone {
            title = "Готово"
            tint = Color.green.opacity(0.82)
        } else {
            title = "Ожидание"
            tint = Color.gray.opacity(0.78)
        }

        return HStack(spacing: 8) {
            if isStoriesDownloadInProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(isDark ? 0.14 : 0.10))
        )
    }

    var downloadsCard: some View {
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

    func logsCard(maxHeight: CGFloat? = nil) -> some View {
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

    func homeLogsCard(maxHeight: CGFloat? = nil) -> some View {
        card("Логи", padding: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Spacer(minLength: 0)

                    Button {
                        model.copyLogs()
                        showingLogsCopiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            showingLogsCopiedFeedback = false
                        }
                    } label: {
                        Label(showingLogsCopiedFeedback ? "Скопировано ✓" : "Скопировать", systemImage: showingLogsCopiedFeedback ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 18)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(model.logs.reversed().enumerated()), id: \.offset) { index, line in
                                Text(cleanedLogLine(line))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(logTint(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    }
                    .frame(maxWidth: .infinity, maxHeight: maxHeight ?? 320, alignment: .topLeading)
                    .onAppear {
                        if !model.logs.isEmpty {
                            proxy.scrollTo(model.logs.count - 1, anchor: .bottom)
                        }
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

    var runtimeCard: some View {
        settingsCard("Техническая информация") {
            VStack(alignment: .leading, spacing: 12) {
                Text(runtimeSummaryHeadline)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup("Показать детали", isExpanded: $showingRuntimeDetails) {
                    horizontalMonospaceField(
                        model.runtimeSummary.isEmpty ? "Информация о среде появится после проверки воркера." : model.runtimeSummary,
                        fontSize: 12
                    )
                    .padding(.top, 8)
                    .transition(.opacity)
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .tint(prominentButtonTint)

                button("Открыть папку среды", systemImage: "internaldrive") {
                    model.openRuntimeDirectory()
                }
            }
        }
    }

    var updatesCard: some View {
        settingsCard("Обновления") {
            VStack(alignment: .leading, spacing: 12) {
                statusInlineNote(
                    title: "Автообновление",
                    message: model.updateSummary
                )

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

                            Text("Проверить обновления")
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(secondaryButtonTint)
                    .disabled(model.isCheckingForUpdates)
                } else {
                    Text("Обновления пока недоступны в этой сборке")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(quaternaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    var powerCard: some View {
        settingsCard("Во время выгрузки") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $model.preventSleepDuringDownloads) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(model.preventSleepDuringDownloads ? prominentButtonTint : secondaryText)

                        Text("Не давать Mac засыпать")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryText)
                    }
                }
                .toggleStyle(.switch)

                if !model.preventSleepDuringDownloads {
                    statusInlineNote(
                        title: "Внимание",
                        message: "Если Mac уснёт во время длинной выгрузки, скачивание stories или Reels может прерваться."
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    var sessionCard: some View {
        settingsCard("Подключение к Instagram") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Если среда ещё не подготовлена, установи компоненты прямо отсюда. После этого можно открыть браузер для входа и проверить сессию.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                statusInlineNote(
                    title: "Авторизация",
                    message: "Браузер для входа держится открытым, пока Instagram не выдаст активную сессию или пока не истечёт таймаут."
                )

                if model.hasEmbeddedRuntime {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.green.opacity(0.86))

                        Text("Всё встроено — дополнительная установка не нужна")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .cardBackground(
                        cornerRadius: controlCornerRadius,
                        fill: cardFill,
                        stroke: cardStroke,
                        tint: Color.green.opacity(isDark ? 0.16 : 0.10)
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    if !model.hasEmbeddedRuntime {
                        button("Установить компоненты", systemImage: "arrow.down.circle") {
                            Task { await model.bootstrapEnvironment() }
                        }

                        button("Проверить готовность", systemImage: "bolt.horizontal.circle") {
                            Task { await model.refreshEnvironment() }
                        }
                    }

                    button("Войти в Instagram", systemImage: "person.crop.circle.badge.checkmark", prominent: true) {
                        Task { await model.login() }
                    }

                    button("Проверить сессию", systemImage: "checkmark.shield") {
                        Task { await model.checkSession() }
                    }
                }
            }
        }
    }

    var downloadModePicker: some View {
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

    var storiesDownloadModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Режим браузера")
                .font(.caption)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(tertiaryText)

            Picker("Режим браузера", selection: $model.downloadMode) {
                ForEach(AppModel.DownloadMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedDownloadModeDescription)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: model.downloadMode)
    }

    var storiesMediaSelectionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Что сохранять")
                .font(.caption)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(tertiaryText)

            Picker("Что сохранять", selection: $model.mediaSelectionMode) {
                ForEach(AppModel.MediaSelectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedMediaSelectionDescription)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: model.mediaSelectionMode)
    }

    var mediaSelectionPicker: some View {
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

    var reelsComposerCard: some View {
        reelsCard("Ссылки на Reels") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Вставь одну или несколько ссылок — каждую с новой строки. Приложение обработает их по очереди.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                reelsInputEditor

                HStack(spacing: 10) {
                    Button {
                        Task { await model.downloadReels() }
                    } label: {
                        HStack(spacing: 8) {
                            if isReelsDownloadInProgress {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Загружаю...")
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Скачать")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(prominentButtonTint)
                    .disabled(reelsLinkCount == 0 || model.isBusy)

                    Button {
                        model.reelsInput = ""
                    } label: {
                        Label("Очистить", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(secondaryButtonTint)
                    .disabled(model.isBusy || model.reelsInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Reels скачиваются отдельным потоком и не зависят от сценария сторис.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(quaternaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isBusy)
    }

    var reelsInputEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.reelsInput)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .scrollContentBackground(.hidden)
                .foregroundStyle(primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .background(Color.clear)
                .frame(minHeight: 160)

            if model.reelsInput.isEmpty {
                Text("Например:\nhttps://www.instagram.com/reel/DMabc123/\nhttps://www.instagram.com/reel/DMxyz456/")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isDark ? 0.08 : 0.78))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .transition(.opacity)
            }

            Text("\(reelsLinkCount) \(reelsLinkCount == 1 ? "ссылка" : reelsLinkCount < 5 ? "ссылки" : "ссылок")")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(quaternaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isDark ? 0.08 : 0.72))
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
        reelsCard("Куда сохранять") {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.saveDirectory.path)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                        Label("Выбрать папку", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(secondaryButtonTint)

                    Button {
                        model.openSaveDirectory()
                    } label: {
                        Label("Показать в Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(secondaryButtonTint)
                }
            }
        }
    }

    var reelsActivityPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            reelsActivityHeader
            reelsDownloadsCard
            reelsLogsCard()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: model.isBusy)
    }

    var reelsActivityHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Активность")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                Spacer(minLength: 0)

                reelsSessionBadge
                    .transition(.opacity)
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
                .transition(.opacity)
            }
        }
    }

    var reelsSessionBadge: some View {
        let ready = model.sessionReady
        return HStack(spacing: 6) {
            Image(systemName: ready ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 11, weight: .semibold))

            Text(ready ? "Сессия активна" : "Нет сессии")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(ready ? Color.green.opacity(0.88) : Color.red.opacity(0.82))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill((ready ? Color.green : Color.red).opacity(isDark ? 0.16 : 0.10))
        )
    }

    var reelsDownloadsCard: some View {
        reelsCard("Последние загрузки", padding: 0) {
            Group {
                if model.downloadedItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(tertiaryText)

                        Text("Пока ничего нет")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.downloadedItems.prefix(20)) { item in
                                reelsDownloadRow(item)
                            }
                        }
                        .padding(18)
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
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)

                    Text(item.localPath)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Button {
                    model.revealDownloadedItem(at: item.localPath)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .tint(secondaryButtonTint)
                .help("Показать в Finder")
            }

            HStack(spacing: 8) {
                Text(formattedFileSize(for: item.localPath))
                Text("·")
                Text(formattedDownloadTime(item.createdAt))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                .fill(itemFill)
        )
    }

    func reelsLogsCard(maxHeight: CGFloat? = nil) -> some View {
        reelsCard("Логи", padding: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Spacer(minLength: 0)

                    Button {
                        model.copyLogs()
                        showingLogsCopiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            showingLogsCopiedFeedback = false
                        }
                    } label: {
                        Label(showingLogsCopiedFeedback ? "Скопировано ✓" : "Скопировать логи", systemImage: showingLogsCopiedFeedback ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 18)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(model.logs.reversed().enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(logTint(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    }
                    .frame(maxWidth: .infinity, maxHeight: maxHeight ?? 280, alignment: .topLeading)
                    .onAppear {
                        if !model.logs.isEmpty {
                            proxy.scrollTo(model.logs.count - 1, anchor: .bottom)
                        }
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

    func logTint(for line: String) -> Color {
        let normalized = line.lowercased()
        if normalized.contains("error") || normalized.contains("failed") {
            return Color.red.opacity(0.84)
        }
        if normalized.contains("ready") || normalized.contains("saved") {
            return Color.green.opacity(0.84)
        }
        return secondaryText
    }

    func formattedFileSize(for path: String) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? NSNumber
        else {
            return "Размер неизвестен"
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
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.batchInput)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .scrollContentBackground(.hidden)
                .foregroundStyle(primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .background(Color.clear)
                .frame(minHeight: 180)

            if model.batchInput.isEmpty {
                Text("По одной ссылке или username на строку.\nНапример:\ndian.vegas1\nhttps://www.instagram.com/stevensetu/\nleftlanepapi")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(tertiaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }

            if !model.batchInput.isEmpty {
                Button {
                    model.batchInput = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isDark ? 0.08 : 0.78))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .transition(.opacity)
            }

            Text("\(batchProfileInputCount) \(batchProfileInputCount == 1 ? "профиль" : batchProfileInputCount < 5 ? "профиля" : "профилей")")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(quaternaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isDark ? 0.08 : 0.72))
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
        .animation(.easeInOut(duration: 0.2), value: batchProfileInputCount)
    }

    var storiesDownloadButton: some View {
        Button {
            Task { await model.runBatchDownloads() }
        } label: {
            HStack(spacing: 8) {
                if isStoriesDownloadInProgress {
                    ProgressView()
                        .controlSize(.small)
                    Text("Загружаю...")
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Скачать")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(queueActionTint)
        .disabled(model.batchQueue.isEmpty || model.isBusy)
    }

    var storiesStopButton: some View {
        Button {
            model.stopBatchDownloads()
        } label: {
            Label("Остановить", systemImage: "stop.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color.red.opacity(0.82))
        .disabled(!model.batchIsRunning)
    }

    func ghostButton(_ title: String, systemImage: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint ?? secondaryButtonTint)
        .disabled(model.isBusy)
    }

    func queueSummaryBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
            )
    }

    func reelsCard<Content: View>(_ title: String, padding: CGFloat = 18, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(quaternaryText)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            content()
                .padding(.horizontal, padding)
                .padding(.bottom, padding == 0 ? 18 : padding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: cardCornerRadius, fill: cardFill, stroke: cardStroke)
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
                status: "Готов",
                accent: Color.green.opacity(0.86),
                backgroundTint: Color.green.opacity(isDark ? 0.16 : 0.10)
            )
        }

        let isError = summary.contains("ошиб") || summary.contains("не удалось") || summary.contains("process") || summary.contains("error")
        return SettingsStatusPresentation(
            symbol: "bolt.fill",
            status: "Ошибка",
            accent: isError ? Color.red.opacity(0.82) : Color.gray.opacity(0.78),
            backgroundTint: isError ? Color.red.opacity(isDark ? 0.14 : 0.08) : Color.gray.opacity(isDark ? 0.12 : 0.07)
        )
    }

    var sessionStatusPresentation: SettingsStatusPresentation {
        let summary = model.sessionSummary.lowercased()
        if model.sessionReady {
            return SettingsStatusPresentation(
                symbol: "person.crop.circle.badge.checkmark",
                status: "Готов",
                accent: Color.green.opacity(0.86),
                backgroundTint: Color.green.opacity(isDark ? 0.16 : 0.10)
            )
        }

        let isError = summary.contains("ошиб") || summary.contains("timeout") || summary.contains("error")
        return SettingsStatusPresentation(
            symbol: "person.crop.circle.badge.checkmark",
            status: isError ? "Ошибка" : "Нет сессии",
            accent: isError ? Color.red.opacity(0.82) : Color.gray.opacity(0.78),
            backgroundTint: isError ? Color.red.opacity(isDark ? 0.14 : 0.08) : Color.gray.opacity(isDark ? 0.12 : 0.07)
        )
    }

    var runtimeSummaryHeadline: String {
        guard !model.runtimeSummary.isEmpty else {
            return "Данные о runtime появятся после проверки воркера."
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
        return "\(runtimeKind) · Playwright · \(browserLabel)"
    }

    func statusCard(title: String, presentation: SettingsStatusPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(presentation.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(presentation.accent.opacity(isDark ? 0.18 : 0.12))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.caption)
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(quaternaryText)

                    Text(presentation.status)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(presentation.accent.opacity(isDark ? 0.18 : 0.12))
                        )
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground(
            cornerRadius: controlCornerRadius,
            fill: cardFill,
            stroke: cardStroke,
            tint: presentation.backgroundTint
        )
        .animation(.easeInOut(duration: 0.2), value: presentation.status)
    }

    var liveStatusBadge: some View {
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

    var stepTracker: some View {
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

    func animatedBusyStepLabel(at date: Date) -> String {
        let base = model.currentStepLabel.isEmpty ? "Идёт подготовка выгрузки" : model.currentStepLabel
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

    func statPill(title: String, value: Int, accent: Color) -> some View {
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

    func statusRailPill(title: String, value: String, detail: String, tint: Color) -> some View {
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

    func queueSummaryPill(title: String, value: String, tint: Color) -> some View {
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

    func settingsCard<Content: View>(_ title: String, padding: CGFloat = 18, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(quaternaryText)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            content()
                .padding(.horizontal, padding)
                .padding(.bottom, padding == 0 ? 18 : padding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: cardCornerRadius, fill: cardFill, stroke: cardStroke)
    }

    func card<Content: View>(_ title: String, padding: CGFloat = 18, @ViewBuilder content: () -> Content) -> some View {
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

    func button(
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

    func batchQueueItem(_ item: AppModel.BatchProfileItem) -> some View {
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

    func statusColor(for status: AppModel.BatchProfileItem.Status) -> Color {
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

    func placeholderBullet(_ text: String) -> some View {
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

    func statusInlineNote(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .tracking(1.2)
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

    var fieldBackground: some View {
        RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
            .fill(inputFill)
    }

    var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardFill)
        }
    }

    var sidebarBackground: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
            Rectangle()
                .fill(glassTint.opacity(isDark ? 0.75 : 0.9))
        }
    }

    var windowBackground: some View {
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

private struct CardBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    let fill: Color
    let stroke: Color
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private extension View {
    func cardBackground(cornerRadius: CGFloat, fill: Color, stroke: Color, tint: Color? = nil) -> some View {
        modifier(CardBackgroundModifier(cornerRadius: cornerRadius, fill: fill, stroke: stroke, tint: tint))
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
