import SwiftUI

struct RootTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var pinpointController: PinpointController
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MainMapScreen(controller: controller, store: store)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .accessibilityIdentifier("mapTab")
                .tag(0)

            PinpointView(controller: pinpointController)
                .tabItem {
                    Label("Pinpoint", systemImage: "scope")
                }
                .accessibilityIdentifier("pinpointTab")
                .tag(1)

            ActivityTabView(controller: controller, store: store)
                .tabItem {
                    Label("Activity", systemImage: "waveform.path.ecg")
                }
                .accessibilityIdentifier("activityTab")
                .tag(2)

            ProgressTabView(store: store, pinpointStore: pinpointController.store)
                .tabItem {
                    Label("Progress", systemImage: "flag.fill")
                }
                .accessibilityIdentifier("progressTab")
                .tag(3)
        }
        .tint(AtlasTheme.blue)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(AtlasTheme.tabBarBackground(for: colorScheme), for: .tabBar)
        .onChange(of: controller.isRecording) { _, isRecording in
            if isRecording {
                selectedTab = 0
            }
        }
    }
}

struct ActivityTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: controller.recorder.activityType.symbolName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AtlasTheme.blue)
                            .frame(width: 44, height: 44)
                            .background(AtlasTheme.blue.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(controller.isRecording ? controller.recorder.activityType.activeTitle : "Ready to explore")
                                .font(.headline)
                            Text(controller.isRecording
                                  ? "Recording \(controller.recorder.activityType.displayName.lowercased()) tiles"
                                  : controller.recorder.activityType.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(ActivityType.selectableCases, id: \.self) { type in
                        Button {
                            controller.setActivityType(type)
                        } label: {
                            ActivityTypeRow(
                                type: type,
                                isSelected: controller.recorder.activityType == type
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isRecording)
                    }
                } header: {
                    Text("Activity type")
                } footer: {
                    Text(controller.isRecording
                          ? "Finish the current session before switching activities."
                          : "Each activity uses its own reveal grid width.")
                }

                Section("This atlas") {
                    HStack(spacing: 0) {
                        StatKPI(value: "\(store.activitiesCompleted)", caption: "Activities")
                        StatKPI(value: "\(store.discoveredTiles.count)", caption: "Tiles", accent: AtlasTheme.teal)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    if let summary = controller.lastSummary {
                        LabeledContent("Last session", value: "+\(summary.tilesDiscovered) new · \(formatDistance(summary.distanceMeters))")
                    }
                }
            }
            .navigationTitle("Activity")
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
    }
}

struct ProgressTabView: View {
    @ObservedObject var store: TileStore
    @ObservedObject var pinpointStore: PinpointStore
    @Environment(\.colorScheme) private var colorScheme

    private var masterySnapshot: MasterySnapshot {
        MasterySnapshot(tiles: store.discoveredTiles)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    explorerHero
                    xpTotalsCard
                    pinpointStatsCard
                    masteryLadderCard
                    revealGridNote
                }
                .padding(20)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Progress")
        }
    }

    // MARK: - Explorer hero

    private var explorerHero: some View {
        StatSectionCard {
            VStack(spacing: 14) {
                Text("\(store.discoveryXPTotal + store.familiarityXPTotal)")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(AtlasTheme.teal)
                Text("Lifetime XP")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 0) {
                    StatKPI(value: "\(store.discoveredTiles.count)", caption: "Tiles")
                    StatKPI(value: "\(store.activitiesCompleted)", caption: "Activities")
                    StatKPI(
                        value: StatsFormat.percent(store.discoveryXPTotal, of: store.discoveryXPTotal + store.familiarityXPTotal),
                        caption: "Discovery"
                    )
                }
            }
        }
    }

    // MARK: - XP totals

    private var xpTotalsCard: some View {
        StatSectionCard {
            HStack(spacing: 16) {
                XPSplitArc(
                    discovery: store.discoveryXPTotal,
                    familiarity: store.familiarityXPTotal,
                    size: 80
                )

                VStack(alignment: .leading, spacing: 12) {
                    xpTotalRow(label: "Discovery", value: store.discoveryXPTotal, color: AtlasTheme.teal)
                    xpTotalRow(label: "Familiarity", value: store.familiarityXPTotal, color: AtlasTheme.gold)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func xpTotalRow(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text("\(value) XP")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
        }
    }

    // MARK: - Pinpoint stats

    private var pinpointStatsCard: some View {
        StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Pinpoint")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "scope")
                        .foregroundStyle(AtlasTheme.blue.opacity(0.5))
                }

                HStack(spacing: 0) {
                    StatKPI(value: "\(pinpointStore.gamesPlayed)", caption: "Games")
                    StatKPI(value: "\(pinpointStore.highScoreWorldwide)", caption: "Worldwide", accent: AtlasTheme.blue)
                    StatKPI(value: "\(pinpointStore.highScoreHomeTurf)", caption: "Home Turf", accent: AtlasTheme.gold)
                }

                HStack {
                    Text("Exact tile hits")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pinpointStore.exactTileHits)")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            }
        }
    }

    // MARK: - Mastery ladder

    private var masteryLadderCard: some View {
        let snap = masterySnapshot
        return StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Mastery ladder")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(snap.total) tiles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                MasteryDistributionBar(counts: snap.orderedCounts.map { (state: $0.state, count: $0.count) }, height: 12)

                VStack(spacing: 6) {
                    ForEach(snap.orderedCounts, id: \.state) { entry in
                        HStack(spacing: 8) {
                            Circle().fill(entry.state.mapStroke).frame(width: 8, height: 8)
                            Text(entry.state.displayName)
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(entry.count)")
                                .font(.caption.weight(.bold).monospacedDigit())
                            Text(StatsFormat.percent(entry.count, of: snap.total))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reveal grid

    private var revealGridNote: some View {
        StatSectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reveal grid")
                        .font(.subheadline.weight(.semibold))
                    Text("Current width: \(store.tileSize.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "hexagon.fill")
                    .font(.title2)
                    .foregroundStyle(AtlasTheme.teal.opacity(0.3))
            }
        }
    }
}

// MARK: - MasterySnapshot

private struct MasterySnapshot {
    struct Entry {
        let state: TileState
        let count: Int
    }

    let orderedCounts: [Entry]
    let total: Int

    init(tiles: [WorldTile]) {
        var buckets: [TileState: Int] = [:]
        for tile in tiles {
            buckets[tile.state, default: 0] += 1
        }
        let states = TileState.allCases.filter { $0 != .fogged }
        orderedCounts = states.map { Entry(state: $0, count: buckets[$0, default: 0]) }
        total = tiles.count
    }
}
