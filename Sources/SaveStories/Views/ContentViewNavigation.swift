import SwiftUI

extension ContentView {
    var sidebar: some View {
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

    func sidebarRow(for section: AppSection) -> some View {
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

    var settingsSidebarButton: some View {
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

    var settingsPopover: some View {
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

    var detailContent: some View {
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
}
