import SwiftUI

extension ContentView {
    var homeTwoView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 900
            ScrollView {
                SaveMeGlassGroup(spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    if compact {
                        homeTwoComposerCard(compact: true)
                        homeTwoQueueCard(compact: true)
                        homeStatusCard
                        homeResultCard
                        recentListsCard(compact: true)
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 20) {
                                homeTwoComposerCard(compact: false)
                                homeTwoQueueCard(compact: false)
                            }
                            .frame(maxWidth: .infinity)
                            VStack(spacing: 20) {
                                homeStatusCard
                                homeResultCard
                                recentListsCard(compact: true)
                            }
                            .frame(width: 310)
                        }
                    }
                    homeDiagnosticsCard(maxHeight: 280)
                }
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, contentHorizontalPadding(for: proxy.size.width))
                .padding(.top, 8)
                .padding(.bottom, 28)
                }
            }
        }
    }

    var reelsView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 980
            let horizontalPadding = contentHorizontalPadding(for: proxy.size.width)

            ScrollView {
                SaveMeGlassGroup(spacing: 0) {
                    VStack(alignment: .leading, spacing: SaveMeMetrics.sectionSpacing) {
                        if compact {
                            reelsComposerCard
                            reelsDestinationCard
                            reelsActivityPanel
                        } else {
                            HStack(alignment: .top, spacing: SaveMeMetrics.sectionSpacing) {
                                VStack(alignment: .leading, spacing: SaveMeMetrics.sectionSpacing) {
                                    reelsComposerCard
                                    reelsDestinationCard
                                }
                                .frame(maxWidth: .infinity, alignment: .top)

                                reelsActivityPanel
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                        }
                    }
                    .frame(maxWidth: 1180, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    var sortingView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 980
            let horizontalPadding = contentHorizontalPadding(for: proxy.size.width)

            ScrollView {
                SaveMeGlassGroup(spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {

                    if compact {
                        VStack(alignment: .leading, spacing: 20) {
                            postProcessingCard
                            emptyFolderCleanupCard
                            logsCard(maxHeight: 320)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            postProcessingCard
                                .frame(maxWidth: .infinity, alignment: .top)
                            VStack(alignment: .leading, spacing: 20) {
                                emptyFolderCleanupCard
                                logsCard(maxHeight: 420)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 28)
                .padding(.top, 8)
                }
            }
        }
    }

    var settingsView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1040
            let horizontalPadding = contentHorizontalPadding(for: proxy.size.width)

            ScrollView {
                SaveMeGlassGroup(spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {

                    if compact {
                        VStack(alignment: .leading, spacing: 20) {
                            settingsStatusSection
                            powerCard
                            updatesCard
                            languageCard
                            sessionCard
                            runtimeCard
                        }
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 20) {
                                powerCard
                                updatesCard
                                languageCard
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
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 28)
                .padding(.top, 8)
                }
            }
        }
    }

    var settingsStatusSection: some View {
        settingsCard(L("Состояние"), symbol: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 12) {
                statusCards

                statusInlineNote(
                    title: L("Последний результат"),
                    message: model.lastResult
                )
            }
        }
    }

    var homeStatusCard: some View {
        card(L("Состояние"), symbol: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 14) {
                homeStatusHeader

                Text(model.statusDetail)
                    .font(.saveMe(.body, .medium))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isBusy {
                    stepTracker
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.3), value: model.isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var homeResultCard: some View {
        card(L("Результат"), symbol: "chart.bar") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                homeResultTile(title: L("Найдено"), value: model.foundStoriesCount, accent: SaveMePalette.warning.opacity(0.78))
                homeResultTile(title: L("Сохранено"), value: model.savedStoriesCount, accent: SaveMePalette.success.opacity(0.78))
                homeResultTile(title: L("Файлов"), value: model.liveDownloadedFileCount, accent: SaveMePalette.info.opacity(0.78))
                homeResultTile(title: L("Папок"), value: model.liveCreatedFolderCount, accent: SaveMePalette.info.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func homeResultTile(title: String, value: Int, accent: Color) -> some View {
        figure(title, "\(value)")
    }
}
