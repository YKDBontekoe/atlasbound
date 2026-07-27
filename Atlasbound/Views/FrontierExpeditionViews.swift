import SwiftUI

struct ExpeditionCard: View {
    let offer: ExpeditionOffer
    let sectorName: String
    let isActive: Bool
    let isCompleted: Bool
    let progress: Int
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(difficultyColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: offer.difficulty.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(difficultyColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(offer.difficulty.displayName)
                            .font(.subheadline.weight(.bold))
                        if isActive {
                            Text("ACTIVE")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(difficultyColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(difficultyColor)
                        } else if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(AtlasTheme.teal)
                        }
                    }
                    Text(sectorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Label("\(offer.targetSectorDistance) sectors", systemImage: "arrow.up.forward")
                        Label("+\(offer.completionBonus)", systemImage: "star.fill")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                if isActive, offer.tilesRequired > 0 {
                    VStack(spacing: 2) {
                        Text("\(progress)/\(offer.tilesRequired)")
                            .font(.caption.weight(.bold).monospacedDigit())
                        Text("tiles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? difficultyColor.opacity(0.08) : Color.secondary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isActive ? difficultyColor.opacity(0.35) : Color.clear, lineWidth: 1.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(isCompleted)
        .accessibilityIdentifier("expeditionCard_\(offer.difficulty.rawValue)")
    }

    private var difficultyColor: Color {
        switch offer.difficulty {
        case .scout: AtlasTheme.teal
        case .trailblazer: AtlasTheme.blue
        case .pathfinder: AtlasTheme.gold
        }
    }
}

struct IdleExpeditionPanel: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore

    private let sectorEngine = HexSectorEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frontier Expeditions")
                        .font(.headline)
                    Text("Weekly offers · \(store.frontierState.weekKey.isEmpty ? "this week" : store.frontierState.weekKey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(controller.weeklyFrontierScore)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(AtlasTheme.gold)
                    Text("weekly pts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let active = controller.activeExpedition {
                ExpeditionCard(
                    offer: active,
                    sectorName: sectorName(for: active),
                    isActive: true,
                    isCompleted: false,
                    progress: controller.targetSectorDiscoveredCount,
                    onSelect: {}
                )

                Button("Abandon expedition") {
                    controller.abandonActiveExpedition()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            ForEach(controller.availableExpeditions) { offer in
                ExpeditionCard(
                    offer: offer,
                    sectorName: sectorName(for: offer),
                    isActive: false,
                    isCompleted: false,
                    progress: 0,
                    onSelect: { controller.selectExpedition(offer) }
                )
            }

            if controller.activeExpedition == nil && controller.availableExpeditions.isEmpty {
                Text("All expeditions completed this week — great work!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }

            Button {
                controller.showMatchingFrontierLeaderboard()
            } label: {
                Label("Frontier leaderboard · \(controller.currentGridLabel)", systemImage: "trophy.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AtlasTheme.blue)
            .accessibilityIdentifier("frontierLeaderboardButton")
        }
        .padding(14)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
        .padding(.horizontal, 12)
    }

    private func sectorName(for offer: ExpeditionOffer) -> String {
        guard let parsed = sectorEngine.parseSectorID(offer.targetSectorID) else { return "Unknown sector" }
        return sectorEngine.displayName(for: parsed.sector)
    }
}

struct ActiveFrontierTracker: View {
    @ObservedObject var controller: WorldController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundStyle(AtlasTheme.gold)
                Text("Frontier")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(controller.sessionFrontierScore) pts")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(AtlasTheme.gold)
            }

            if let offer = controller.activeExpedition {
                HStack(spacing: 8) {
                    Image(systemName: offer.difficulty.iconName)
                        .foregroundStyle(AtlasTheme.blue)
                    Text(offer.difficulty.displayName)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(controller.targetSectorDiscoveredCount)/\(offer.tilesRequired) target tiles")
                        .font(.caption.weight(.medium).monospacedDigit())
                }

                ProgressView(
                    value: Double(controller.targetSectorDiscoveredCount),
                    total: Double(max(1, offer.tilesRequired))
                )
                .tint(AtlasTheme.blue)

                HStack(spacing: 12) {
                    Label(
                        controller.targetSectorConnected ? "Connected" : "Not connected",
                        systemImage: controller.targetSectorConnected ? "link" : "link.badge.plus"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(controller.targetSectorConnected ? AtlasTheme.teal : .secondary)

                    Spacer()

                    Label(
                        String(format: "x%.1f combo", controller.frontierComboMultiplier),
                        systemImage: "flame.fill"
                    )
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(controller.frontierCombo.isActive ? AtlasTheme.gold : .secondary)
                }
            } else {
                Text("Select an expedition before your next walk to earn frontier points.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: controller.sessionFrontierScore)
    }
}

struct FrontierComboCard: View {
    @ObservedObject var controller: WorldController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AtlasTheme.gold)
                Text("Frontier combo")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "x%.1f", controller.frontierComboMultiplier))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AtlasTheme.gold)
            }

            ProgressView(value: max(0.08, controller.frontierComboProgress))
                .tint(AtlasTheme.gold)

            HStack {
                Text("Connected frontier tiles boost points")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(controller.frontierComboRemainingLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
    }
}
