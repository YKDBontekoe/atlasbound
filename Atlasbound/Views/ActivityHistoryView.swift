import SwiftUI

/// Full list of finished activity sessions, newest first.
struct ActivityHistoryView: View {
    @ObservedObject var activityHistory: ActivityHistoryStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSession: PersistedActivityRecord?

    private var sessions: [PersistedActivityRecord] {
        activityHistory.sessions.reversed()
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                List(sessions) { session in
                    Button {
                        selectedSession = session
                    } label: {
                        ActivityHistoryRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Recent Activities")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSession) { session in
            ActivitySessionDetailView(session: session) {
                selectedSession = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No activities yet", systemImage: "figure.walk")
        } description: {
            Text("Finish a recording session to see it here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
    }
}

struct ActivityHistoryRow: View {
    let session: PersistedActivityRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.activityType.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(session.activityType.statsMapColor)
                .frame(width: 40, height: 40)
                .background(session.activityType.statsMapColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.activityType.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("+\(session.totalXP) XP")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AtlasTheme.teal)
                }
                Text(ActivityHistoryFormat.sessionTimestamp(session.endedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(StatsFormat.distance(session.distanceMeters))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                HStack(spacing: 6) {
                    Text(StatsFormat.duration(session.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if session.tilesDiscovered > 0 {
                        Text("· \(session.tilesDiscovered) new")
                            .font(.caption2)
                            .foregroundStyle(AtlasTheme.teal)
                    }
                }
                if session.frontierSessionTotal > 0 {
                    Text("+\(session.frontierSessionTotal) frontier")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AtlasTheme.gold)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Read-only session detail for a persisted activity record.
struct ActivitySessionDetailView: View {
    let session: PersistedActivityRecord
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    heroHeader
                    kpiBand
                    if session.frontierSessionTotal > 0 {
                        frontierCard
                    }
                    sessionMetaCard
                    nerdStrip
                }
                .padding(20)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var heroHeader: some View {
        StatSectionCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(session.activityType.statsMapColor.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: session.activityType.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(session.activityType.statsMapColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.activityType.activeTitle)
                        .font(.title3.weight(.bold))
                    Text(ActivityHistoryFormat.sessionTimestamp(session.endedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("+\(session.totalXP)")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Text("XP earned")
                            .font(.subheadline)
                    }
                    .foregroundStyle(AtlasTheme.teal)
                }
                Spacer()
            }
        }
    }

    private var kpiBand: some View {
        StatSectionCard {
            HStack(spacing: 0) {
                StatKPI(
                    value: StatsFormat.distance(session.distanceMeters),
                    caption: "Distance"
                )
                detailDivider
                StatKPI(
                    value: StatsFormat.duration(session.duration),
                    caption: "Duration"
                )
                detailDivider
                StatKPI(
                    value: "\(session.tilesDiscovered)",
                    caption: "New tiles",
                    accent: AtlasTheme.teal
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var frontierCard: some View {
        StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Frontier contribution")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("+\(session.frontierSessionTotal)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(AtlasTheme.gold)
                }

                HStack(spacing: 0) {
                    StatKPI(
                        value: "+\(session.frontierPoints ?? 0)",
                        caption: "Tile pts",
                        accent: AtlasTheme.gold
                    )
                    detailDivider
                    StatKPI(
                        value: session.frontierConnectionBonus.map { "+\($0)" } ?? "—",
                        caption: "Connection"
                    )
                    detailDivider
                    StatKPI(
                        value: session.frontierCompletionBonus.map { "+\($0)" } ?? "—",
                        caption: "Complete"
                    )
                }

                if let weekly = session.frontierWeeklyTotal {
                    NerdStat(label: "Weekly total", value: "\(weekly) pts", icon: "calendar")
                }
            }
        }
    }

    private var sessionMetaCard: some View {
        StatSectionCard {
            VStack(spacing: 8) {
                NerdStat(
                    label: "Reveal grid",
                    value: "\(session.tileSizeMeters) m",
                    icon: "hexagon.fill"
                )
                NerdStat(
                    label: "Started",
                    value: ActivityHistoryFormat.sessionTimestamp(session.startedAt),
                    icon: "play.fill"
                )
                NerdStat(
                    label: "Finished",
                    value: ActivityHistoryFormat.sessionTimestamp(session.endedAt),
                    icon: "flag.checkered"
                )
            }
        }
    }

    private var nerdStrip: some View {
        StatSectionCard {
            VStack(spacing: 8) {
                if let xpKm = StatsFormat.xpPerKm(session.totalXP, meters: session.distanceMeters) {
                    NerdStat(label: "XP density", value: xpKm, icon: "bolt.fill")
                }
                if let rate = StatsFormat.rate(session.tilesDiscovered, duration: session.duration) {
                    NerdStat(label: "Discovery rate", value: rate, icon: "hexagon.fill")
                }
                if let pace = StatsFormat.pace(session.distanceMeters, duration: session.duration) {
                    NerdStat(label: "Avg pace", value: pace, icon: "speedometer")
                }
            }
        }
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(AtlasTheme.divider(for: colorScheme))
            .frame(width: 1, height: 32)
    }
}

enum ActivityHistoryFormat {
    static func sessionTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
