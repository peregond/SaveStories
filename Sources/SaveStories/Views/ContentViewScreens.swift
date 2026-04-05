import SwiftUI

extension ContentView {
    var homeTwoView: some View {
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

    var batchView: some View {
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

    var reelsView: some View {
        HStack(spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHero(
                        eyebrow: "Reels",
                        title: "Скачать Reels по ссылке",
                        subtitle: "Выгрузка Reels тут"
                    )

                    reelsComposerCard
                    reelsDestinationCard
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)

            reelsActivityPanel
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    var settingsView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1040

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailHero(
                        eyebrow: "Настройки",
                        title: "Параметры приложения",
                        subtitle: "Экран для обновлений, поведения во время выгрузки, состояния воркера и Instagram-сессии. Всё собрано в одном месте без всплывающих окон."
                    )

                    settingsOverviewCard

                    if compact {
                        VStack(alignment: .leading, spacing: 20) {
                            settingsStatusSection
                            powerCard
                            updatesCard
                            sessionCard
                            runtimeCard
                        }
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 20) {
                                powerCard
                                updatesCard
                            }
                            .frame(maxWidth: .infinity, alignment: .top)

                            VStack(alignment: .leading, spacing: 20) {
                                settingsStatusSection
                                sessionCard
                                runtimeCard
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

    var settingsOverviewCard: some View {
        settingsCard("Обзор") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Текущая версия")
                            .font(.caption)
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(tertiaryText)

                        Text(versionLabel)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(primaryText)
                    }

                    Spacer(minLength: 0)

                    if model.isBusy {
                        liveStatusBadge
                            .frame(maxWidth: 280, alignment: .trailing)
                    }
                }

                Text("По умолчанию приложение не даёт ноутбуку заснуть во время активной выгрузки stories или Reels. При этом проверки среды, логин и проверка обновлений работают отдельно и не мешают обычной работе системы.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var settingsStatusSection: some View {
        settingsCard("Состояние") {
            VStack(alignment: .leading, spacing: 12) {
                statusCards

                statusInlineNote(
                    title: "Последний результат",
                    message: model.lastResult
                )
            }
        }
    }

    func homeTwoHero(compact: Bool) -> some View {
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

    var homeHeroTitleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stories")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)

            Text("Скачать сторис из Instagram")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Добавь профили, выбери настройки и запусти одной кнопкой.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var homeHeroVersionBlock: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(versionLabel)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(tertiaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isDark ? 0.08 : 0.58))
                )

            if model.batchIsRunning {
                liveStatusBadge
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    var homeStatusCard: some View {
        card("Состояние") {
            VStack(alignment: .leading, spacing: 14) {
                homeStatusBadge

                Text(model.statusDetail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                stepTracker
            }
        }
        .frame(maxWidth: .infinity, minHeight: 224, maxHeight: .infinity, alignment: .topLeading)
    }

    var homeResultCard: some View {
        card("Результат") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                homeResultTile(title: "Профилей", value: model.foundStoriesCount, accent: Color.orange.opacity(0.78))
                homeResultTile(title: "Сохранено", value: model.savedStoriesCount, accent: Color.green.opacity(0.78))
                homeResultTile(title: "Файлов", value: model.liveDownloadedFileCount, accent: Color.blue.opacity(0.78))
                homeResultTile(title: "Папок", value: model.liveCreatedFolderCount, accent: Color.mint.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 224, maxHeight: .infinity, alignment: .topLeading)
    }

    var statusRail: some View {
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

    func homeResultTile(title: String, value: Int, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.caption)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(tertiaryText)
            }

            Text("\(value)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(pillFill)
        )
    }
}
