import SwiftUI

extension ContentView {
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SaveMe")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                Text("Stories и Reels")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tertiaryText)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 6) {
                ForEach([AppSection.main, AppSection.batch, AppSection.reels, AppSection.sorting]) { section in
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

            VStack(alignment: .leading, spacing: 8) {
                if let readyUpdateVersion = model.readyUpdateVersion {
                    Button {
                        model.installReadyUpdate()
                    } label: {
                        Label("Обновить", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(prominentButtonTint)
                    .disabled(model.isBusy)
                    .help("Установить SaveMe \(readyUpdateVersion)")
                }

                Text("v\(versionLabel)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(quaternaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)

            Button {
                selectedSection = .settings
            } label: {
                sidebarRow(for: .settings)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(minWidth: sidebarWidth, idealWidth: sidebarWidth, maxWidth: sidebarWidth)
        .padding(.top, topContentInset)
        .background(
            sidebarBackground
                .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(isDark ? 0.05 : 0.35))
                .frame(width: 1)
                .ignoresSafeArea(edges: .top)
        }
    }

    func sidebarRow(for section: AppSection) -> some View {
        let isSelected = selectedSection == section

        return HStack(spacing: 12) {
            sidebarIcon(for: section, isSelected: isSelected)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isSelected ? prominentButtonTint.opacity(0.85) : Color.white.opacity(isDark ? 0.06 : 0.42))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)

                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(quaternaryText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? prominentButtonTint.opacity(isDark ? 0.18 : 0.14) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.white.opacity(isDark ? 0.08 : 0.34) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    func sidebarIcon(for section: AppSection, isSelected: Bool) -> some View {
        if let emoji = section.sidebarEmoji {
            Text(emoji)
                .font(.system(size: 15))
        } else {
            Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : primaryText)
        }
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
            case .sorting:
                sortingView
            case .settings:
                settingsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, topContentInset)
    }
}
