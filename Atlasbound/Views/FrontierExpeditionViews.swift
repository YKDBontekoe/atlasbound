import SwiftUI

struct ExpeditionCard: View {
    let offer: ExpeditionOffer
    let sectorName: String
    let isActive: Bool
    let isCompleted: Bool
    let progress: Int
    let onSelect: () -> Void
    var onAbandon: (() -> Void)?

    @State private var showAbandonConfirmation = false

    var body: some View {
        Group {
            if isCompleted || isActive {
                cardContent
            } else {
                Button(action: onSelect) {
                    cardContent
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("expeditionCard_\(offer.difficulty.rawValue)")
        .confirmationDialog(
            "Abandon this expedition?",
            isPresented: $showAbandonConfirmation,
            titleVisibility: .visible
        ) {
            Button("Abandon expedition", role: .destructive) {
                onAbandon?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Progress on \(sectorName) will be lost. You can pick another offer this week.")
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(difficultyColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: offer.difficulty.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(difficultyColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(sectorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

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

                Text(difficultySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Label("+\(offer.completionBonus) pts", systemImage: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AtlasTheme.gold)

                if isActive, offer.tilesRequired > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(
                            value: Double(progress),
                            total: Double(max(1, offer.tilesRequired))
                        )
                        .tint(difficultyColor)

                        Text("\(progress)/\(offer.tilesRequired) tiles")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if isActive, onAbandon != nil {
                Menu {
                    Button("Abandon expedition", role: .destructive) {
                        showAbandonConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityIdentifier("abandonExpeditionButton")
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isActive ? difficultyColor.opacity(0.35) : Color.clear, lineWidth: 1.5)
                }
        }
        .opacity(isCompleted ? 0.65 : 1)
    }

    private var difficultySubtitle: String {
        let sectors = offer.targetSectorDistance
        let sectorLabel = sectors == 1 ? "1 sector away" : "\(sectors) sectors away"
        return "\(offer.difficulty.displayName) · \(sectorLabel)"
    }

    private var cardFill: Color {
        if isCompleted {
            return Color.secondary.opacity(0.04)
        }
        return isActive ? difficultyColor.opacity(0.08) : Color.secondary.opacity(0.06)
    }

    private var difficultyColor: Color {
        offer.difficulty.tint
    }
}

struct ExpeditionMissionList: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore

    private var completedExpeditions: [ExpeditionOffer] {
        let completed = Set(store.frontierState.completedOfferIDs)
        return store.frontierState.offers.filter { completed.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                weekHeader

                if let active = controller.activeExpedition {
                    sectionHeader("Active expedition")
                    ExpeditionCard(
                        offer: active,
                        sectorName: controller.sectorDisplayName(for: active),
                        isActive: true,
                        isCompleted: false,
                        progress: controller.targetSectorDiscoveredCount,
                        onSelect: {},
                        onAbandon: { controller.abandonActiveExpedition() }
                    )
                }

                if !controller.availableExpeditions.isEmpty {
                    sectionHeader("Available this week")
                    ForEach(controller.availableExpeditions) { offer in
                        ExpeditionCard(
                            offer: offer,
                            sectorName: controller.sectorDisplayName(for: offer),
                            isActive: false,
                            isCompleted: false,
                            progress: 0,
                            onSelect: { controller.selectExpedition(offer) }
                        )
                    }
                }

                if !completedExpeditions.isEmpty {
                    sectionHeader("Completed")
                    ForEach(completedExpeditions) { offer in
                        ExpeditionCard(
                            offer: offer,
                            sectorName: controller.sectorDisplayName(for: offer),
                            isActive: false,
                            isCompleted: true,
                            progress: offer.tilesRequired,
                            onSelect: {}
                        )
                    }
                }

                if controller.activeExpedition == nil
                    && controller.availableExpeditions.isEmpty
                    && completedExpeditions.isEmpty {
                    Text("Weekly expeditions will appear here once frontier offers are generated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else if controller.activeExpedition == nil && controller.availableExpeditions.isEmpty {
                    Text("All expeditions completed this week — great work!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var weekHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(FrontierEngine.friendlyWeekLabel(for: store.frontierState.weekKey))
                    .font(.subheadline.weight(.semibold))
                Text("Weekly frontier offers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(controller.weeklyFrontierScore)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(AtlasTheme.gold)
                Text("weekly pts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// Full-screen sheet for browsing and selecting weekly frontier expeditions.
struct ExpeditionSheet: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExpeditionMissionList(controller: controller, store: store)
                .navigationTitle("Frontier Expeditions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            controller.showMatchingFrontierLeaderboard()
                        } label: {
                            Image(systemName: "trophy.fill")
                        }
                        .accessibilityLabel("Frontier leaderboard")
                        .accessibilityIdentifier("frontierLeaderboardButton")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .accessibilityIdentifier("expeditionSheet")
    }
}

/// Compact map banner — tap to open the full expedition sheet.
struct FrontierMissionBanner: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(bannerTint.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: bannerIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(bannerTint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(secondaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let trailing = trailingBadge {
                    Text(trailing)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AtlasTheme.gold)
                }

                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                GlassChrome(
                    shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                    weight: .regular
                )
            }
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("frontierMissionBanner")
        .accessibilityLabel(primaryLabel)
        .accessibilityHint("Opens weekly frontier expeditions")
    }

    private var primaryLabel: String {
        if let active = controller.activeExpedition {
            return controller.sectorDisplayName(for: active)
        }
        let count = controller.availableExpeditions.count
        if count > 0 {
            return count == 1 ? "1 weekly expedition" : "\(count) weekly expeditions"
        }
        return "Week complete"
    }

    private var secondaryLabel: String {
        if let active = controller.activeExpedition {
            return "\(active.difficulty.displayName) · \(controller.targetSectorDiscoveredCount)/\(active.tilesRequired) tiles"
        }
        if !controller.availableExpeditions.isEmpty {
            return "Tap to choose a target sector"
        }
        return "\(controller.weeklyFrontierScore) pts this week"
    }

    private var trailingBadge: String? {
        if controller.activeExpedition != nil {
            return nil
        }
        if !controller.availableExpeditions.isEmpty {
            return "\(controller.weeklyFrontierScore) pts"
        }
        return nil
    }

    private var bannerIcon: String {
        if controller.activeExpedition != nil {
            return controller.activeExpedition?.difficulty.iconName ?? "flag.fill"
        }
        return controller.availableExpeditions.isEmpty ? "checkmark.seal.fill" : "flag.fill"
    }

    private var bannerTint: Color {
        if let active = controller.activeExpedition {
            return active.difficulty.tint
        }
        return controller.availableExpeditions.isEmpty ? AtlasTheme.teal : AtlasTheme.gold
    }
}

struct ActiveFrontierTracker: View {
    @ObservedObject var controller: WorldController
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let offer = controller.activeExpedition {
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
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

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: offer.difficulty.iconName)
                            .foregroundStyle(offer.difficulty.tint)
                        Text(controller.sectorDisplayName(for: offer))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text("\(controller.targetSectorDiscoveredCount)/\(offer.tilesRequired) tiles")
                            .font(.caption.weight(.medium).monospacedDigit())
                    }

                    if !compact {
                        Text(offer.difficulty.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(
                    value: Double(controller.targetSectorDiscoveredCount),
                    total: Double(max(1, offer.tilesRequired))
                )
                .tint(offer.difficulty.tint)

                if !compact {
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

                    VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: max(0.08, controller.frontierComboProgress))
                        .tint(AtlasTheme.gold)

                    HStack {
                        Text("Combo from connected frontier tiles")
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
                }
            }
            .padding(compact ? 10 : 14)
            .background {
                GlassChrome(
                    shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                    weight: .regular
                )
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: controller.sessionFrontierScore)
        }
    }
}
