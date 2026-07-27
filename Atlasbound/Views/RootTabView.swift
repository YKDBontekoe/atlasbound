import SwiftUI
import CoreLocation

struct RootTabView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var activityHistory: ActivityHistoryStore
    @ObservedObject var regionLookup: RegionLookupStore
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

            ActivityTabView(
                controller: controller,
                store: store,
                activityHistory: activityHistory
            )
                .tabItem {
                    Label("Activity", systemImage: "waveform.path.ecg")
                }
                .accessibilityIdentifier("activityTab")
                .tag(2)

            ProgressTabView(
                store: store,
                activityHistory: activityHistory,
                regionLookup: regionLookup,
                pinpointStore: pinpointController.store,
                controller: controller
            )
                .tabItem {
                    Label("Progress", systemImage: "flag.fill")
                }
                .accessibilityIdentifier("progressTab")
                .tag(3)
        }
        .tint(AtlasTheme.blue)
        .toolbar(pinpointController.isGameInProgress ? .hidden : .visible, for: .tabBar)
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
    @ObservedObject var activityHistory: ActivityHistoryStore

    @State private var selectedSession: PersistedActivityRecord?

    private var recentSessions: [PersistedActivityRecord] {
        Array(activityHistory.sessions.suffix(3).reversed())
    }

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

                Section {
                    if recentSessions.isEmpty {
                        ContentUnavailableView {
                            Label("No sessions yet", systemImage: "clock.arrow.circlepath")
                        } description: {
                            Text("Your finished activities will appear here.")
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(recentSessions) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                ActivityHistoryRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }

                        NavigationLink {
                            ActivityHistoryView(activityHistory: activityHistory)
                        } label: {
                            Text("See all activities")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("seeAllActivities")
                    }
                } header: {
                    Text("Recent activities")
                }

                Section("This atlas") {
                    HStack(spacing: 0) {
                        StatKPI(value: "\(store.activitiesCompleted)", caption: "Activities")
                        StatKPI(value: "\(store.discoveredTiles.count)", caption: "Tiles", accent: AtlasTheme.teal)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    if let summary = controller.lastSummary {
                        LabeledContent("Last session", value: "+\(summary.tilesDiscovered) new · \(StatsFormat.distance(summary.distanceMeters))")
                    }
                }
            }
            .navigationTitle("Activity")
            .sheet(item: $selectedSession) { session in
                ActivitySessionDetailView(session: session) {
                    selectedSession = nil
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

struct ProgressTabView: View {
    @ObservedObject var store: TileStore
    @ObservedObject var activityHistory: ActivityHistoryStore
    @ObservedObject var regionLookup: RegionLookupStore
    @ObservedObject var pinpointStore: PinpointStore
    @ObservedObject var controller: WorldController
    @Environment(\.colorScheme) private var colorScheme

    @State private var mapLayer: AtlasStatsMapLayer = .mastery
    @State private var showExplorerMap = false

    private var tilesBySize: [Int: [WorldTile]] { store.allDiscoveredTilesBySize }

    private var allTiles: [WorldTile] {
        StatsEngine.allDiscoveredTiles(from: tilesBySize)
    }

    private var territory: StatsEngine.TerritorySummary {
        StatsEngine.totalUnlockedArea(tilesBySize: tilesBySize)
    }

    private var placesVisited: StatsEngine.PlacesVisitedSummary {
        regionLookup.placesVisited(tilesBySize: tilesBySize)
    }

    private var masteryBreakdown: [StatsEngine.MasteryEntry] {
        StatsEngine.masteryBreakdown(tiles: store.discoveredTiles)
    }

    private var activityFootprint: [StatsEngine.ActivityFootprintEntry] {
        StatsEngine.activityFootprint(tiles: allTiles)
    }

    private var explorerCenters: [CLLocationCoordinate2D] {
        tilesBySize.flatMap { size, tiles in
            StatsEngine.tileCenters(tiles: tiles, tileSizeMeters: size)
        }
    }

    private var discoveryRange: (first: Date?, latest: Date?) {
        StatsEngine.discoveryDateRange(tiles: allTiles)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    territoryCard
                    if !placesVisited.isEmpty || regionLookup.isResolving {
                        placesVisitedCard
                    }
                    frontierStatsCard
                    personalRecordsCard
                    if !activityFootprint.isEmpty {
                        activityFootprintCard
                    }
                    atlasMapCard
                    explorerVitalsCard
                    explorerHero
                    xpTotalsCard
                    pinpointStatsCard
                    masteryLadderCard
                    revealGridNote
                }
                .padding(20)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Atlas Stats")
            .task(id: store.discoveredTiles.count) {
                regionLookup.resolve(tilesBySize: tilesBySize)
            }
            .sheet(isPresented: $showExplorerMap) {
                AtlasExplorerMapScreen(
                    tilesBySize: tilesBySize,
                    currentGridSize: store.tileSize.rawValue,
                    layer: $mapLayer,
                    frontierChargedTileIDs: Set(store.frontierState.chargedTileIDs)
                )
            }
        }
    }

    // MARK: - Territory

    private var territoryCard: some View {
        let km2 = territory.totalAreaSquareMeters / 1_000_000
        return StatSectionCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Territory conquered")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "map.fill")
                        .foregroundStyle(AtlasTheme.teal.opacity(0.5))
                }

                Text(StatsFormat.areaSquareKilometers(territory.totalAreaSquareMeters))
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(AtlasTheme.teal)
                    .accessibilityIdentifier("territoryArea")

                if let comparison = StatsFormat.areaComparison(km2) {
                    Text(comparison)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    StatKPI(value: "\(territory.totalTileCount)", caption: "Tiles")
                    StatKPI(
                        value: "\(territory.gridBreakdown.count)",
                        caption: "Grids",
                        accent: AtlasTheme.blue
                    )
                    StatKPI(
                        value: StatsFormat.areaSquareKilometers(territory.totalAreaSquareMeters),
                        caption: "Total"
                    )
                }

                if !territory.gridBreakdown.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(territory.gridBreakdown, id: \.tileSizeMeters) { entry in
                            HStack(spacing: 8) {
                                Text("\(entry.tileSizeMeters) m grid")
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text("\(entry.tileCount) tiles")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                Text(StatsFormat.areaSquareKilometers(entry.areaSquareMeters))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 72, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Places visited

    private var placesVisitedCard: some View {
        let places = placesVisited
        return StatSectionCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Places visited")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "globe.europe.africa.fill")
                        .foregroundStyle(AtlasTheme.blue.opacity(0.55))
                }

                HStack(spacing: 0) {
                    if !places.countries.isEmpty {
                        StatKPI(
                            value: "\(places.countries.count)",
                            caption: "Countries",
                            accent: AtlasTheme.blue
                        )
                    }
                    if !places.provinces.isEmpty {
                        StatKPI(
                            value: "\(places.provinces.count)",
                            caption: "Provinces"
                        )
                    }
                    if !places.cities.isEmpty {
                        StatKPI(
                            value: "\(places.cities.count)",
                            caption: "Cities",
                            accent: AtlasTheme.teal
                        )
                    }
                    if places.isEmpty {
                        StatKPI(value: "…", caption: "Resolving")
                    }
                }

                if regionLookup.isResolving {
                    Text("Updating places…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                placeList(title: "Countries", entries: places.countries)
                placeList(title: "Provinces / states", entries: places.provinces)
                placeList(title: "Cities", entries: places.cities)
            }
        }
        .accessibilityIdentifier("placesVisitedCard")
    }

    @ViewBuilder
    private func placeList(title: String, entries: [StatsEngine.PlaceEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                let visible = Array(entries.prefix(8))
                ForEach(visible, id: \.key) { entry in
                    HStack(spacing: 8) {
                        Text(entry.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text("\(entry.tileCount)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if entries.count > visible.count {
                    Text("+\(entries.count - visible.count) more")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Frontier

    private var frontierStatsCard: some View {
        let state = store.frontierState
        return StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Frontier")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "flag.2.crossed.fill")
                        .foregroundStyle(AtlasTheme.gold.opacity(0.6))
                }

                HStack(spacing: 0) {
                    StatKPI(value: "\(state.weeklyScore)", caption: "This week", accent: AtlasTheme.gold)
                    StatKPI(value: "\(state.completedOfferIDs.count)", caption: "Completed")
                    StatKPI(value: "\(max(state.bestWeekScore, state.weeklyScore))", caption: "Best week")
                }

                if !state.weekKey.isEmpty {
                    NerdStat(label: "Week", value: state.weekKey, icon: "calendar")
                }
                NerdStat(
                    label: "Lifetime expeditions",
                    value: "\(state.lifetimeCompletedExpeditions)",
                    icon: "map.fill"
                )

                Button {
                    controller.showMatchingFrontierLeaderboard()
                } label: {
                    Label("Leaderboard · \(store.tileSize.label) grid", systemImage: "trophy.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AtlasTheme.blue)
                .accessibilityIdentifier("progressFrontierLeaderboard")
            }
        }
    }

    // MARK: - Personal records

    private var personalRecordsCard: some View {
        let ranked = ActivityType.selectableCases
            .map { type in (type, activityHistory.totalDistance(for: type)) }
            .sorted { $0.1 > $1.1 }

        return StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Personal records")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Longest session")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(ranked.enumerated()), id: \.element.0) { index, entry in
                    let type = entry.0
                    let longest = activityHistory.longestDistance(for: type)
                    let total = activityHistory.totalDistance(for: type)
                    let sessions = activityHistory.sessionCount(for: type)

                    HStack(spacing: 10) {
                        medalIcon(rank: index)
                        Image(systemName: type.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(type.statsMapColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                                .font(.caption.weight(.semibold))
                            if sessions > 0 {
                                Text("\(StatsFormat.distance(total)) total · \(sessions) sessions")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No sessions yet")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Text(longest > 0 ? StatsFormat.distance(longest) : "—")
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func medalIcon(rank: Int) -> some View {
        switch rank {
        case 0:
            Image(systemName: "medal.fill")
                .foregroundStyle(AtlasTheme.gold)
                .font(.caption)
        case 1:
            Image(systemName: "medal.fill")
                .foregroundStyle(AtlasTheme.slate)
                .font(.caption)
        case 2:
            Image(systemName: "medal.fill")
                .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.28))
                .font(.caption)
        default:
            Color.clear.frame(width: 14, height: 14)
        }
    }

    // MARK: - Activity footprint

    private var activityFootprintCard: some View {
        let total = activityFootprint.reduce(0) { $0 + $1.tileCount }
        return StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Activity footprint")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Tiles stamped")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                SegmentedBar(
                    segments: activityFootprint.map { ($0.activity.statsMapColor, Double($0.tileCount)) },
                    height: 10
                )
                .frame(height: 10)

                VStack(spacing: 6) {
                    ForEach(activityFootprint, id: \.activity) { entry in
                        HStack(spacing: 8) {
                            Circle().fill(entry.activity.statsMapColor).frame(width: 8, height: 8)
                            Text(entry.activity.displayName)
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(entry.tileCount)")
                                .font(.caption.weight(.bold).monospacedDigit())
                            Text(StatsFormat.percent(entry.tileCount, of: total))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Atlas map

    private var atlasMapCard: some View {
        StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Atlas explorer")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Expand") {
                        showExplorerMap = true
                    }
                    .font(.caption.weight(.semibold))
                }

                if allTiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "hexagon")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("Discover tiles to unlock your atlas map")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                } else {
                    AtlasStatsMapView(
                        tilesBySize: tilesBySize,
                        currentGridSize: store.tileSize.rawValue,
                        layer: $mapLayer,
                        frontierChargedTileIDs: Set(store.frontierState.chargedTileIDs),
                        interactive: true,
                        height: 220
                    )
                }
            }
        }
    }

    // MARK: - Explorer vitals

    private var explorerVitalsCard: some View {
        let span = StatsEngine.explorerSpanMeters(centers: explorerCenters)
        let activeDays = StatsEngine.activeExplorationDays(tiles: allTiles)
        let deepMastery = StatsEngine.deepMasteryCount(tiles: allTiles)
        let range = discoveryRange

        return StatSectionCard {
            VStack(spacing: 10) {
                HStack {
                    Text("Explorer vitals")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }

                NerdStat(
                    label: "Atlas wingspan",
                    value: span > 0 ? StatsFormat.distance(span) : "—",
                    icon: "arrow.left.and.right"
                )
                NerdStat(
                    label: "Active exploration days",
                    value: "\(activeDays)",
                    icon: "calendar"
                )
                NerdStat(
                    label: "First discovery",
                    value: StatsFormat.shortDate(range.first),
                    icon: "flag.fill"
                )
                NerdStat(
                    label: "Latest discovery",
                    value: StatsFormat.shortDate(range.latest),
                    icon: "sparkles"
                )
                NerdStat(
                    label: "Mastered + legendary",
                    value: "\(deepMastery)",
                    icon: "star.fill"
                )
            }
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
        let entries = masteryBreakdown
        let total = entries.reduce(0) { $0 + $1.count }
        return StatSectionCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Mastery ladder")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(total) tiles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                MasteryDistributionBar(counts: entries.map { (state: $0.state, count: $0.count) }, height: 12)

                VStack(spacing: 6) {
                    ForEach(entries, id: \.state) { entry in
                        HStack(spacing: 8) {
                            Circle().fill(entry.state.mapStroke).frame(width: 8, height: 8)
                            Text(entry.state.displayName)
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(entry.count)")
                                .font(.caption.weight(.bold).monospacedDigit())
                            Text(StatsFormat.percent(entry.count, of: total))
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
