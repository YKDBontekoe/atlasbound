import SwiftUI

struct ActivitySummaryView: View {
    let summary: ActivitySummary
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedXP = 0

    private var revisited: Int { max(0, summary.tilesVisited - summary.tilesDiscovered) }
    private var frontierIndexOffset: Int {
        (summary.frontierContribution?.sessionTotal ?? 0) > 0 ? 1 : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    heroHeader
                        .staggeredAppear(index: 0)
                    kpiBand
                        .staggeredAppear(index: 1)
                    if let frontier = summary.frontierContribution, frontier.sessionTotal > 0 {
                        frontierCard(frontier)
                            .staggeredAppear(index: 2)
                    }
                    tileCompositionCard
                        .staggeredAppear(index: 2 + frontierIndexOffset)
                    xpBreakdownCard
                        .staggeredAppear(index: 3 + frontierIndexOffset)
                    nerdStrip
                        .staggeredAppear(index: 4 + frontierIndexOffset)
                }
                .padding(20)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Activity Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                AtlasHaptics.success()
                guard !reduceMotion else {
                    displayedXP = summary.totalXP
                    return
                }
                displayedXP = 0
                withAnimation(AtlasMotion.celebrate) {
                    displayedXP = summary.totalXP
                }
            }
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        StatSectionCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AtlasTheme.blue.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: summary.activityType.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AtlasTheme.blue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.activityType.activeTitle)
                        .font(.title3.weight(.bold))
                    HStack(spacing: 4) {
                        Text("+\(displayedXP)")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .contentTransition(.numericText())
                            .animation(AtlasMotion.number, value: displayedXP)
                        Text("XP earned")
                            .font(.subheadline)
                    }
                    .foregroundStyle(AtlasTheme.teal)
                }
                Spacer()
            }
        }
    }

    // MARK: - KPI Band

    private var kpiBand: some View {
        StatSectionCard {
            HStack(spacing: 0) {
                StatKPI(
                    value: StatsFormat.distance(summary.distanceMeters),
                    caption: "Distance"
                )
                divider
                StatKPI(
                    value: StatsFormat.duration(summary.duration),
                    caption: "Duration"
                )
                divider
                StatKPI(
                    value: "\(summary.tilesDiscovered)",
                    caption: "New tiles",
                    accent: AtlasTheme.teal
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(AtlasTheme.divider(for: colorScheme))
            .frame(width: 1, height: 32)
    }

    // MARK: - Frontier

    private func frontierCard(_ frontier: FrontierSessionContribution) -> some View {
        StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Frontier contribution")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("+\(frontier.sessionTotal)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(AtlasTheme.gold)
                }

                HStack(spacing: 0) {
                    StatKPI(value: "+\(frontier.tilePoints)", caption: "Tile pts", accent: AtlasTheme.gold)
                    divider
                    StatKPI(
                        value: frontier.connectionBonus > 0 ? "+\(frontier.connectionBonus)" : "—",
                        caption: "Connection"
                    )
                    divider
                    StatKPI(
                        value: frontier.completionBonus > 0 ? "+\(frontier.completionBonus)" : "—",
                        caption: "Complete"
                    )
                }

                if frontier.targetTilesRequired > 0 {
                    NerdStat(
                        label: "Target sector",
                        value: "\(frontier.targetTilesDiscovered)/\(frontier.targetTilesRequired) tiles",
                        icon: "scope"
                    )
                }
                if frontier.didConnectTarget {
                    NerdStat(label: "Sector link", value: "Connected", icon: "link")
                }
                NerdStat(
                    label: "Weekly total",
                    value: "\(frontier.weeklyTotalAfter) pts",
                    icon: "calendar"
                )
                if frontier.comboPeak > 1 {
                    NerdStat(
                        label: "Peak combo",
                        value: String(format: "x%.1f", frontier.comboPeak),
                        icon: "flame.fill"
                    )
                }
            }
        }
    }

    // MARK: - Tile composition

    private var tileCompositionCard: some View {
        StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Tile composition")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(summary.tilesVisited) visited")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                SegmentedBar(segments: [
                    (color: AtlasTheme.teal, value: Double(summary.tilesDiscovered)),
                    (color: AtlasTheme.slate, value: Double(revisited))
                ], height: 10)

                HStack(spacing: 16) {
                    legendDot(color: AtlasTheme.teal,
                              label: "New",
                              value: "\(summary.tilesDiscovered)",
                              pct: StatsFormat.percent(summary.tilesDiscovered, of: summary.tilesVisited))
                    legendDot(color: AtlasTheme.slate,
                              label: "Revisited",
                              value: "\(revisited)",
                              pct: StatsFormat.percent(revisited, of: summary.tilesVisited))
                    Spacer()
                }
            }
        }
    }

    private func legendDot(color: Color, label: String, value: String, pct: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
            Text(pct)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - XP breakdown

    private var xpBreakdownCard: some View {
        StatSectionCard {
            HStack(spacing: 16) {
                XPSplitArc(discovery: summary.discoveryXP, familiarity: summary.familiarityXP)

                VStack(alignment: .leading, spacing: 10) {
                    xpRow(label: "Discovery",
                          value: summary.discoveryXP,
                          color: AtlasTheme.teal,
                          pct: StatsFormat.percent(summary.discoveryXP, of: summary.totalXP))
                    xpRow(label: "Familiarity",
                          value: summary.familiarityXP,
                          color: AtlasTheme.gold,
                          pct: StatsFormat.percent(summary.familiarityXP, of: summary.totalXP))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func xpRow(label: String, value: Int, color: Color, pct: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("+\(value)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Text(pct)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Nerd strip

    private var nerdStrip: some View {
        StatSectionCard {
            VStack(spacing: 8) {
                if let xpKm = StatsFormat.xpPerKm(summary.totalXP, meters: summary.distanceMeters) {
                    NerdStat(label: "XP density", value: xpKm, icon: "bolt.fill")
                }
                if let rate = StatsFormat.rate(summary.tilesDiscovered, duration: summary.duration) {
                    NerdStat(label: "Discovery rate", value: rate, icon: "hexagon.fill")
                }
                if let pace = StatsFormat.pace(summary.distanceMeters, duration: summary.duration) {
                    NerdStat(label: "Avg pace", value: pace, icon: "speedometer")
                }
                if summary.totalXP > 0 {
                    NerdStat(
                        label: "Discovery share",
                        value: StatsFormat.percent(summary.discoveryXP, of: summary.totalXP),
                        icon: "chart.pie.fill"
                    )
                }
                NerdStat(label: "GPS samples", value: "\(summary.sampleCount)", icon: "location.fill")
            }
        }
    }
}
