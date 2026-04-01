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
            Text("Главная")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)

            Text("Собери очередь, быстро проверь состояние выгрузки и при необходимости вернись к последнему сохранённому набору без переключений между экранами.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var homeHeroVersionBlock: some View {
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

    var homeStatusCard: some View {
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

    var homeResultCard: some View {
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
}
