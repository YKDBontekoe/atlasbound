import SwiftUI

/// Frontier expedition shortcut beneath the primary treasure adventure.
struct MapMissionsStrip: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    let onExpeditionsTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var frontierLabels: FrontierMissionBannerLabels {
        FrontierMissionBannerLabels.make(controller: controller)
    }

    var body: some View {
        HStack(spacing: 0) {
            missionSegment(
                icon: frontierLabels.iconName,
                tint: frontierLabels.tint,
                title: "Expeditions",
                label: frontierLabels.compactLabel,
                badge: frontierLabels.trailingBadge,
                badgeTint: AtlasTheme.gold,
                action: onExpeditionsTap
            )
            .accessibilityIdentifier("mapMissionsExpeditions")
            .accessibilityLabel("Expeditions, \(frontierLabels.compactLabel)")
            .accessibilityHint("Opens weekly frontier expeditions")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
        .padding(.horizontal, 12)
    }

    private func missionSegment(
        icon: String,
        tint: Color,
        title: String,
        label: String,
        badge: String?,
        badgeTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(badgeTint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
