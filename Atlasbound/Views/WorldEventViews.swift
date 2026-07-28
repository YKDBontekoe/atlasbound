import SwiftUI

struct WorldEventBannerLabels: Sendable {
    let primaryLabel: String
    let secondaryLabel: String
    let trailingBadge: String?
    let iconName: String
    let isLiveEvent: Bool
    let visitedHotspotCount: Int
    let hotspotCount: Int

    /// Short label for the combined map missions strip.
    var compactLabel: String {
        if isLiveEvent {
            return primaryLabel
        }
        let total = max(1, hotspotCount)
        return "\(visitedHotspotCount)/\(total)"
    }

    @MainActor
    static func make(controller: WorldController, store: TileStore) -> WorldEventBannerLabels {
        let visited = store.worldEventState.visitedHotspotIDs.count
        let hotspots = store.worldEventState.dailyHotspotTileIDs.count

        let primary: String
        if let live = controller.liveWorldEvent {
            primary = live.title
        } else if let active = store.worldEventState.activeEvent {
            primary = active.title
        } else {
            primary = hotspots > 0 ? "\(hotspots) daily hotspots" : "World events"
        }

        let secondary: String
        if let live = controller.liveWorldEvent {
            let progress = controller.worldEventProgressLabel
            let remaining = WorldEventEngine.remainingLabel(until: live.windowEnd)
            if live.tilesRequired > 0 {
                secondary = "\(progress) · \(remaining)"
            } else {
                secondary = "\(live.subtitle) · \(remaining)"
            }
        } else if store.worldEventState.isActiveCompleted {
            secondary = "Completed — see you next window"
        } else {
            let total = max(1, hotspots)
            secondary = "Hotspots \(visited)/\(total) · tap for schedule"
        }

        let trailing: String?
        if controller.liveWorldEvent != nil {
            let label = controller.worldEventProgressLabel
            trailing = label.isEmpty ? nil : label
        } else {
            trailing = nil
        }

        let icon = controller.liveWorldEvent?.kind.iconName
            ?? store.worldEventState.activeEvent?.kind.iconName
            ?? "sparkles"

        return WorldEventBannerLabels(
            primaryLabel: primary,
            secondaryLabel: secondary,
            trailingBadge: trailing,
            iconName: icon,
            isLiveEvent: controller.liveWorldEvent != nil,
            visitedHotspotCount: visited,
            hotspotCount: hotspots
        )
    }
}

/// Compact map banner for the live client-scheduled world event.
struct WorldEventBanner: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    let onTap: () -> Void

    private var labels: WorldEventBannerLabels {
        WorldEventBannerLabels.make(controller: controller, store: store)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AtlasTheme.eventAccent.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: labels.iconName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AtlasTheme.eventAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(labels.primaryLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(labels.secondaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let trailing = labels.trailingBadge {
                    Text(trailing)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AtlasTheme.eventAccent)
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
        .accessibilityIdentifier("worldEventBanner")
        .accessibilityLabel(labels.primaryLabel)
        .accessibilityHint("Opens world event details")
    }
}

/// Sheet describing the current world event, hotspots, and schedule.
struct WorldEventSheet: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let event = store.worldEventState.activeEvent {
                        eventCard(event)
                    } else {
                        Text("No scheduled event right now. Daily hotspots still mark nearby frontier hexes to explore.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    hotspotSection

                    scheduleSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("World Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("worldEventSheet")
        .onAppear {
            controller.refreshWorldEventPresentation()
        }
    }

    private func eventCard(_ event: WorldEventInstance) -> some View {
        let live = event.isLive
        let progress = WorldEventEngine().progressToward(active: event, state: store.worldEventState)
        let completed = store.worldEventState.completedEventSet.contains(event.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AtlasTheme.eventAccent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: event.kind.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AtlasTheme.eventAccent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(event.title)
                            .font(.headline)
                        if live {
                            Text("LIVE")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AtlasTheme.eventAccent.opacity(0.15), in: Capsule())
                                .foregroundStyle(AtlasTheme.eventAccent)
                        } else if completed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AtlasTheme.teal)
                        }
                    }
                    Text(event.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let sectorID = event.targetSectorID {
                Label(controller.sectorDisplayName(forSectorID: sectorID), systemImage: "flag.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AtlasTheme.eventAccent)
            }

            if event.tilesRequired > 0 {
                ProgressView(
                    value: Double(min(progress, event.tilesRequired)),
                    total: Double(max(1, event.tilesRequired))
                )
                .tint(AtlasTheme.eventAccent)
                Text("\(min(progress, event.tilesRequired))/\(event.tilesRequired)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            bonusRows(for: event)

            Text(live
                 ? WorldEventEngine.remainingLabel(until: event.windowEnd)
                 : "Window \(Self.hourFormatter.string(from: event.windowStart))–\(Self.hourFormatter.string(from: event.windowEnd)) UTC")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AtlasTheme.eventAccent.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AtlasTheme.eventAccent.opacity(live ? 0.35 : 0.12), lineWidth: 1.5)
                }
        }
    }

    @ViewBuilder
    private func bonusRows(for event: WorldEventInstance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if event.discoveryXPMultiplier > 1 {
                Label(
                    String(format: "%.0f%% discovery XP", (event.discoveryXPMultiplier - 1) * 100),
                    systemImage: "bolt.fill"
                )
            }
            if event.familiarityXPMultiplier > 1 {
                Label(
                    String(format: "%.0f%% familiarity XP", (event.familiarityXPMultiplier - 1) * 100),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            if event.frontierScoreMultiplier > 1 {
                Label(
                    String(format: "%.0f%% frontier score", (event.frontierScoreMultiplier - 1) * 100),
                    systemImage: "flame.fill"
                )
            }
            if event.completionFamiliarityXP > 0 {
                Label("+\(event.completionFamiliarityXP) familiarity on complete", systemImage: "star.fill")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private var hotspotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily hotspots")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            let total = store.worldEventState.dailyHotspotTileIDs.count
            let visited = store.worldEventState.visitedHotspotIDs.count
            Text(total == 0
                  ? "Hotspots appear near your frontier once location is ready."
                  : "\(visited)/\(total) visited today — marked on the map.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today’s schedule")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            let kind = WorldEventEngine.catalogKind(for: .now)
            let window = WorldEventEngine.eventWindow(for: kind, on: .now)
            HStack {
                Image(systemName: kind.iconName)
                    .foregroundStyle(AtlasTheme.eventAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(Self.hourFormatter.string(from: window.start))–\(Self.hourFormatter.string(from: window.end)) UTC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Events rotate daily for every explorer — no server required.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("H:mm")
        return formatter
    }()
}

/// Compact in-session tracker when a world event is live.
struct ActiveWorldEventTracker: View {
    @ObservedObject var controller: WorldController
    var compact = false

    var body: some View {
        if let event = controller.liveWorldEvent {
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                HStack {
                    Image(systemName: event.kind.iconName)
                        .foregroundStyle(AtlasTheme.eventAccent)
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(controller.worldEventProgressLabel)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(AtlasTheme.eventAccent)
                }

                if event.tilesRequired > 0 {
                    let progress = WorldEventEngine().progressToward(
                        active: event,
                        state: controller.worldEventState
                    )
                    ProgressView(
                        value: Double(min(progress, event.tilesRequired)),
                        total: Double(max(1, event.tilesRequired))
                    )
                    .tint(AtlasTheme.eventAccent)
                }

                if !compact {
                    Text(WorldEventEngine.remainingLabel(until: event.windowEnd))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(compact ? 10 : 14)
            .background {
                GlassChrome(
                    shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                    weight: .regular
                )
            }
        }
    }
}
