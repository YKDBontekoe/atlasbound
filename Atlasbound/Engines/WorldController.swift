import Foundation
import CoreLocation
import Combine

/// Coordinates recording, tile conversion, progression, and persistence for a session.
@MainActor
final class WorldController: ObservableObject {
    @Published private(set) var liveRoute: [CLLocationCoordinate2D] = []
    @Published private(set) var sessionVisitedTileIDs: Set<String> = []
    /// Tile IDs first discovered during the active session (map highlight).
    @Published private(set) var sessionDiscoveredIDs: Set<String> = []
    @Published private(set) var sessionDiscoveredCount = 0
    @Published private(set) var frontierCombo = FrontierComboState.empty
    @Published private(set) var sessionFrontierScore = 0
    @Published private(set) var frontierScoreCallouts: [FrontierScoreCallout] = []
    @Published private(set) var sessionFeedback: [SessionFeedbackEvent] = []
    @Published private(set) var lastSummary: ActivitySummary?
    @Published private(set) var explorationMode: ExplorationMode = .idle

    let recorder: ActivityRecorder
    let store: TileStore
    let activityHistory: ActivityHistoryStore
    let regionLookup: RegionLookupStore
    let gameCenterManager: GameCenterManager
    let treasureStore: TreasureStore
    let inventoryStore: InventoryStore
    private let progression = ProgressionEngine()
    private let frontierEngine = FrontierEngine()
    private let sectorEngine = HexSectorEngine()
    private let territoryEngine = TerritoryEngine()
    private let landmarkResolver: any LandmarkResolving

    /// Tiles mutated during the active session (merged into store on stop).
    private var sessionTiles: [String: WorldTile] = [:]
    private var sessionProgress = SessionProgress.empty
    private var sessionFrontier = FrontierSessionContribution.empty
    private var scoredFrontierTiles: Set<String> = []
    private var automaticPreviousSample: LocationSample?
    private var automaticVisitedTileIDs: Set<String> = []
    private var treasurePreparationTask: Task<Void, Never>?
    private var treasurePreparationDayKey: String?

    private static let selectedActivityKey = "atlasbound.selectedActivityType"

    init(
        store: TileStore,
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore? = nil,
        gameCenterManager: GameCenterManager? = nil,
        treasureStore: TreasureStore? = nil,
        inventoryStore: InventoryStore? = nil,
        recorder: ActivityRecorder? = nil,
        landmarkResolver: any LandmarkResolving = LandmarkResolver()
    ) {
        self.store = store
        self.activityHistory = activityHistory
        self.regionLookup = regionLookup ?? RegionLookupStore()
        self.gameCenterManager = gameCenterManager ?? GameCenterManager()
        self.treasureStore = treasureStore ?? TreasureStore()
        self.inventoryStore = inventoryStore ?? InventoryStore()
        self.recorder = recorder ?? ActivityRecorder()
        self.landmarkResolver = landmarkResolver
        restoreSelectedActivityType()
        syncRecorderSettings()

        self.recorder.onSample = { [weak self] sample in
            self?.handleSample(sample)
        }
        self.recorder.onPassiveSample = { [weak self] sample in
            self?.handleAutomaticSample(sample)
        }
        refreshFrontierPresentation()
    }

    var isRecording: Bool { recorder.isRecording && explorationMode.isExplicitSession }
    var isPaused: Bool { recorder.isPaused }
    var isQuickExploring: Bool { explorationMode == .quickExplore }
    var isTrackingActivity: Bool { explorationMode == .trackedActivity }
    var isAutomaticExplorationEnabled: Bool { recorder.automaticExplorationEnabled }

    var tileEngine: TileEngine { store.tileEngine }

    var frontierState: FrontierState { store.frontierState }

    var territoryState: TerritoryState { store.territoryState }

    var activeExpedition: ExpeditionOffer? { store.frontierState.activeOffer }

    var availableExpeditions: [ExpeditionOffer] { store.frontierState.availableOffers }

    var weeklyFrontierScore: Int { store.frontierState.weeklyScore }

    var currentSectorName: String {
        guard let coordinate = playerTileCoordinate else { return "Frontier" }
        let sector = sectorEngine.sectorCoordinate(for: coordinate)
        return sectorEngine.displayName(for: sector)
    }

    func sectorDisplayName(for offer: ExpeditionOffer) -> String {
        guard let parsed = sectorEngine.parseSectorID(offer.targetSectorID) else {
            return "Unknown sector"
        }
        return sectorEngine.displayName(for: parsed.sector)
    }

    var currentSectorCompletionPercent: Int {
        guard let coordinate = playerTileCoordinate else { return 0 }
        let sector = sectorEngine.sectorCoordinate(for: coordinate)
        return sectorEngine.completionPercent(
            sector: sector,
            discoveredTileIDs: store.discoveredTileIDs,
            tileEngine: tileEngine
        )
    }

    var treasureTargetCoordinate: CLLocationCoordinate2D? {
        guard let target = treasureStore.currentTarget,
              let axial = tileEngine.parseTileID(target.tileID) else { return nil }
        return tileEngine.centerCoordinate(for: axial)
    }

    var discoveredTileCount: Int { store.discoveredTileCount }

    var frontierComboMultiplier: Double {
        frontierCombo.multiplier
    }

    var frontierComboProgress: Double {
        guard frontierCombo.isActive else { return 0 }
        return Double(frontierCombo.count % 10) / 10.0
    }

    var frontierComboRemainingLabel: String {
        guard let expires = frontierCombo.expiresAt, frontierCombo.isActive else { return "—" }
        let remaining = max(0, expires.timeIntervalSinceNow)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d remaining", minutes, seconds)
    }

    var targetSectorDiscoveredCount: Int {
        guard let offer = activeExpedition else { return 0 }
        return frontierEngine.targetSectorDiscoveredCount(
            offer: offer,
            tiles: mergedTiles,
            tileEngine: tileEngine
        )
    }

    var targetSectorConnected: Bool {
        guard let offer = activeExpedition else { return false }
        let discovered = frontierEngine.discoveredTileCoordinates(from: mergedTiles)
        let territory = frontierEngine.territoryAnchor(
            playerTile: playerTileCoordinate,
            discovered: discovered
        )
        return frontierEngine.routeConnectsTerritoryToSector(
            territory: territory,
            discovered: discovered,
            targetSectorID: offer.targetSectorID,
            tileEngine: tileEngine
        )
    }

    var frontierEdgeTileIDs: Set<String> {
        let discovered = frontierEngine.discoveredTileCoordinates(from: mergedTiles)
        let territory = frontierEngine.territoryAnchor(
            playerTile: playerTileCoordinate,
            discovered: discovered
        )
        let frontier = frontierEngine.frontierTileCoordinates(territory: territory, discovered: discovered)
        return Set(frontier.map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: tileEngine.tileSizeMeters)
        })
    }

    var targetSectorBoundaryTileIDs: Set<String> {
        guard let offer = activeExpedition,
              let parsed = sectorEngine.parseSectorID(offer.targetSectorID) else {
            return []
        }
        return Set(sectorEngine.boundaryTiles(for: parsed.sector).map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: tileEngine.tileSizeMeters)
        })
    }

    var expeditionBeaconCoordinate: CLLocationCoordinate2D? {
        guard let offer = activeExpedition,
              let parsed = sectorEngine.parseSectorID(offer.targetSectorID) else {
            return nil
        }
        let center = sectorEngine.centerTile(for: parsed.sector)
        return tileEngine.centerCoordinate(for: center)
    }

    var territoryPresence: TerritoryPresenceSnapshot {
        territoryEngine.presenceSnapshot(
            playerTile: playerTileCoordinate,
            state: store.territoryState,
            discoveredTileIDs: store.discoveredTileIDs,
            tileEngine: tileEngine
        )
    }

    var claimedSectorBoundaryTileIDs: Set<String> {
        territoryEngine.claimedBoundaryTileIDs(
            state: store.territoryState,
            sizeMeters: tileEngine.tileSizeMeters
        )
    }

    var homeBaseCoordinate: CLLocationCoordinate2D? {
        guard let homeID = store.territoryState.homeSectorID,
              let center = territoryEngine.centerCoordinate(forSectorID: homeID, tileEngine: tileEngine) else {
            return nil
        }
        return tileEngine.centerCoordinate(for: TileCoordinate(q: center.q, r: center.r))
    }

    var placeMapPins: [PlaceMapPin] {
        let pins = regionLookup.successfulLabels.compactMap { cellKey, place -> PlaceMapPin? in
            guard let name = place.locality ?? place.administrativeArea else { return nil }
            guard let coordinate = RegionLookupEngine.representativeCoordinate(forCellKey: cellKey) else { return nil }
            return PlaceMapPin(
                id: cellKey,
                name: name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
        return Array(
            pins.sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
            .prefix(AtlasTheme.maxVisiblePlacePins)
        )
    }

    private var playerTileCoordinate: TileCoordinate? {
        recorder.lastLocation.map { tileEngine.axialCoordinate(for: $0.coordinate) }
    }

    private var mergedTiles: [String: WorldTile] {
        var merged = store.tiles
        for (id, tile) in sessionTiles {
            merged[id] = tile
        }
        return merged
    }

    func nearbyUndiscoveredCount(around coordinate: CLLocationCoordinate2D?, radius: Int = 3) -> Int {
        guard let coordinate else { return 0 }
        let engine = tileEngine
        let center = engine.axialCoordinate(for: coordinate)
        return engine.ring(around: center, radius: radius).filter { axial in
            let id = TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: engine.tileSizeMeters)
            let tile = store.tiles[id]
            return tile == nil || tile?.state == .fogged
        }.count
    }

    func nearbyFogTiles(around coordinate: CLLocationCoordinate2D?, radius: Int = 5) -> [TileCoordinate] {
        guard let coordinate else { return [] }
        let engine = tileEngine
        let center = engine.axialCoordinate(for: coordinate)
        let effectiveRadius = radius + (inventoryStore.hasFogLanternActive ? FieldFindConstants.fogLanternRadiusBonus : 0)
        return engine.ring(around: center, radius: effectiveRadius).filter { axial in
            let id = TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: engine.tileSizeMeters)
            let tile = sessionTiles[id] ?? store.tiles[id]
            return tile == nil || tile?.state == .fogged
        }
    }

    var fieldFindPreviews: [FieldFindPreview] {
        inventoryStore.previewFinds(
            around: playerTileCoordinate,
            tileEngine: tileEngine,
            discoveredTileIDs: store.discoveredTileIDs
        )
    }

    /// Use / activate inventory items with world side effects.
    @discardableResult
    func performItemAction(itemID: String, action: ItemActionKind) -> ItemActionResult? {
        guard let def = ItemCatalog.definition(for: itemID) else { return nil }
        switch action {
        case .use:
            let result = inventoryStore.useItem(itemID: itemID)
            if let result, result.grantedFamiliarityXP > 0 || result.grantedDiscoveryXP > 0 {
                store.addXP(discovery: result.grantedDiscoveryXP, familiarity: result.grantedFamiliarityXP)
            }
            if def.effectKind == .streakOil, result != nil {
                frontierCombo = inventoryStore.consumeStreakOil(combo: frontierCombo)
            }
            if result != nil { AtlasHaptics.success() }
            return result
        case .activate:
            return activateInventoryItem(itemID: itemID, definition: def)
        case .salvage:
            let result = inventoryStore.salvage(itemID: itemID)
            if result != nil { AtlasHaptics.select() }
            return result
        case .discard:
            let result = inventoryStore.discard(itemID: itemID)
            if result != nil { AtlasHaptics.select() }
            return result
        case .assemble, .collect:
            return nil
        }
    }

    @discardableResult
    func assembleRecipe(recipeID: String) -> ItemActionResult? {
        let result = inventoryStore.assemble(recipeID: recipeID)
        if result != nil { AtlasHaptics.success() }
        return result
    }

    private func activateInventoryItem(itemID: String, definition: ItemDefinition) -> ItemActionResult? {
        let vaultHint: String = {
            let keys = treasureStore.weeklyVault.keys
            let need = TreasureConstants.keysRequiredForVault
            if treasureStore.weeklyVault.isCompleted {
                return "This week’s vault already rests open."
            }
            if treasureStore.weeklyVault.isUnlocked {
                return "The vault is unlocked — follow the map marker."
            }
            return "Vault keys \(keys)/\(need). Keep finishing daily trails."
        }()

        let playerTileID = playerTileCoordinate.map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: tileEngine.tileSizeMeters)
        }

        guard let result = inventoryStore.activateItem(
            itemID: itemID,
            playerTileID: playerTileID,
            vaultHint: vaultHint
        ) else { return nil }

        switch definition.effectKind {
        case .trailReroll:
            treasureStore.grantFreeReroll()
        case .surveyBeacon:
            applySurveyBeaconPulse()
        default:
            break
        }
        AtlasHaptics.success()
        objectWillChange.send()
        return result
    }

    private func applySurveyBeaconPulse() {
        guard let center = playerTileCoordinate else { return }
        let engine = tileEngine
        var updated: [WorldTile] = []
        let centerID = TileEngine.makeTileID(q: center.q, r: center.r, sizeMeters: engine.tileSizeMeters)
        let neighbors = engine.ring(around: center, radius: 1)

        func bump(_ id: String, amount: Int) {
            guard var tile = sessionTiles[id] ?? store.tiles[id], tile.isDiscovered else { return }
            progression.applyMasteryPulse(tile: &tile, amount: amount)
            if explorationMode.isExplicitSession {
                sessionTiles[id] = tile
            }
            updated.append(tile)
        }

        bump(centerID, amount: FieldFindConstants.surveyBeaconMasteryXP)
        for axial in neighbors {
            let id = TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: engine.tileSizeMeters)
            guard id != centerID else { continue }
            bump(id, amount: FieldFindConstants.surveyBeaconNeighborXP)
        }
        if !updated.isEmpty {
            store.applyLiveVisitProgress(updatedTiles: updated, discoveryXP: 0, familiarityXP: 0)
        }
    }

    func sectorDisplayName(forSectorID sectorID: String) -> String {
        guard let parsed = sectorEngine.parseSectorID(sectorID) else {
            return "Event sector"
        }
        return sectorEngine.displayName(for: parsed.sector)
    }

    func prepareLocation() {
        recorder.requestAuthorization()
        // Foreground discovery is the default game loop. Background discovery remains
        // separately opt-in because it requires Always location authorization.
        recorder.setAutomaticExploration(
            foreground: true,
            background: recorder.automaticBackgroundEnabled
        )
        if !isRecording {
            explorationMode = .automatic
        }
        recorder.startMonitoringIfNeeded()
        store.applyWeeklyChargeResetIfNeeded()
        refreshFrontierPresentation()
        prepareTreasureTrail()
        gameCenterManager.authenticate()
    }

    func setActivityType(_ type: ActivityType) {
        guard !recorder.isRecording else { return }
        guard type != .unknown else { return }
        recorder.activityType = type
        UserDefaults.standard.set(type.rawValue, forKey: Self.selectedActivityKey)
        refreshFrontierPresentation()
    }

    func selectExpedition(_ offer: ExpeditionOffer) {
        guard !recorder.isRecording else { return }
        store.updateFrontierState({ state in
            var next = state
            next.activeOfferID = offer.id
            return next
        }, playerTile: playerTileCoordinate)
        refreshFrontierPresentation()
    }

    func abandonActiveExpedition() {
        guard !recorder.isRecording else { return }
        store.updateFrontierState({ state in
            var next = state
            next.activeOfferID = nil
            return next
        }, playerTile: playerTileCoordinate)
        refreshFrontierPresentation()
    }

    @discardableResult
    func claimCurrentSector() -> Bool {
        guard let sectorID = territoryPresence.playerSectorID else { return false }
        return claimSector(sectorID)
    }

    @discardableResult
    func claimSector(_ sectorID: String) -> Bool {
        guard let next = territoryEngine.claimSector(
            sectorID: sectorID,
            state: store.territoryState,
            playerTile: playerTileCoordinate,
            discoveredTileIDs: store.discoveredTileIDs,
            tileEngine: tileEngine
        ) else {
            return false
        }
        store.updateTerritoryState { _ in next }
        AtlasHaptics.success()
        objectWillChange.send()
        return true
    }

    @discardableResult
    func setHomeBase(sectorID: String) -> Bool {
        guard let next = territoryEngine.setHomeBase(
            sectorID: sectorID,
            state: store.territoryState
        ) else {
            return false
        }
        store.updateTerritoryState { _ in next }
        AtlasHaptics.success()
        objectWillChange.send()
        return true
    }

    @discardableResult
    func setHomeBaseToCurrentSector() -> Bool {
        guard let sectorID = territoryPresence.playerSectorID else { return false }
        return setHomeBase(sectorID: sectorID)
    }

    func territoryDisplayName(forSectorID sectorID: String) -> String {
        territoryEngine.displayName(forSectorID: sectorID)
    }

    func canSetHomeBase(sectorID: String) -> Bool {
        territoryEngine.canSetHomeBase(sectorID: sectorID, state: store.territoryState)
    }

    private func restoreSelectedActivityType() {
        guard let raw = UserDefaults.standard.string(forKey: Self.selectedActivityKey),
              let type = ActivityType(rawValue: raw),
              type != .unknown else {
            return
        }
        recorder.activityType = type
    }

    func startActivity() {
        beginSession(mode: .trackedActivity)
    }

    func startQuickExplore() {
        beginSession(mode: .quickExplore)
    }

    private func beginSession(mode: ExplorationMode) {
        guard mode == .quickExplore || mode == .trackedActivity else { return }
        guard !recorder.isRecording, recorder.start() else { return }
        store.applyWeeklyChargeResetIfNeeded()
        refreshFrontierPresentation()
        liveRoute = []
        sessionVisitedTileIDs = []
        sessionDiscoveredIDs = []
        sessionDiscoveredCount = 0
        frontierCombo = .empty
        sessionFrontierScore = 0
        frontierScoreCallouts = []
        sessionFeedback = []
        sessionTiles = [:]
        sessionProgress = .empty
        sessionFrontier = .empty
        scoredFrontierTiles = []
        automaticPreviousSample = nil
        if let offer = activeExpedition {
            sessionFrontier.targetTilesRequired = offer.tilesRequired
            sessionFrontier.targetTilesDiscovered = targetSectorDiscoveredCount
        }
        lastSummary = nil
        AtlasHaptics.prepare()
        explorationMode = mode
        store.setDeferPersistence(true)
    }

    func pauseActivity() {
        store.flushToDiskIfNeeded()
        recorder.pause()
    }

    func resumeActivity() {
        recorder.resume()
    }

    func togglePause() {
        recorder.togglePause()
    }

    func stopActivity() {
        guard let result = recorder.stop() else { return }
        let completedMode = explorationMode
        explorationMode = .idle

        let engine = tileEngine
        let covering = engine.tileIDsCoveringRoute(result.samples)
        processTileIDs(covering, at: result.endedAt, activity: recorder.activityType)

        store.setDeferPersistence(false, flush: true)
        store.applySessionProgress(
            sessionProgress,
            updatedTiles: sessionTiles,
            countsAsActivity: completedMode == .trackedActivity
        )

        sessionFrontier.weeklyTotalAfter = store.frontierState.weeklyScore

        if completedMode == .trackedActivity {
            let summary = ActivitySummary(
                id: UUID(),
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                distanceMeters: result.distance,
                sampleCount: result.samples.count,
                tilesVisited: sessionProgress.tilesVisited,
                tilesDiscovered: sessionProgress.tilesDiscovered,
                discoveryXP: sessionProgress.discoveryXP,
                familiarityXP: sessionProgress.familiarityXP,
                activityType: recorder.activityType,
                frontierContribution: sessionFrontier,
                activeDuration: result.activeDuration
            )
            activityHistory.record(summary)
            lastSummary = summary
        }
        frontierCombo = .empty
        frontierScoreCallouts = []
        regionLookup.resolve(tiles: store.discoveredTiles)
        automaticPreviousSample = nil
        if recorder.automaticExplorationEnabled {
            explorationMode = .automatic
            recorder.startMonitoringIfNeeded()
        }

        Task {
            await gameCenterManager.submitFrontierScore(store.frontierState.weeklyScore)
        }
    }

    func refreshFrontierPresentation() {
        store.refreshFrontierState(playerTile: playerTileCoordinate)
    }

    func setAutomaticExploration(foreground: Bool, background: Bool) {
        recorder.setAutomaticExploration(foreground: foreground, background: background)
        if foreground {
            explorationMode = isRecording ? explorationMode : .automatic
            prepareTreasureTrail()
        } else if !isRecording {
            explorationMode = .idle
            automaticPreviousSample = nil
            automaticVisitedTileIDs = []
        }
    }

    func resolveTreasureEncounter(choice: TreasureChoice) {
        guard let reward = treasureStore.resolveEncounter(choice: choice) else { return }
        store.addXP(discovery: 0, familiarity: reward.familiarityXP)
        prepareTreasureTrail()
        AtlasHaptics.success()
    }

    func rerollTreasureTrail() {
        guard let playerTileCoordinate else { return }
        treasurePreparationTask?.cancel()
        treasurePreparationTask = nil
        treasureStore.reroll(anchor: playerTileCoordinate, tileEngine: tileEngine)
    }

    func prepareTreasureTrail() {
        guard let playerTileCoordinate, let location = recorder.lastLocation else { return }
        treasureStore.ensureTrail(anchor: playerTileCoordinate, tileEngine: tileEngine)
        treasureStore.ensureVaultTarget(anchor: playerTileCoordinate, tileEngine: tileEngine)
        guard let dayKey = treasureStore.dailyTrail?.dayKey,
              treasureStore.dailyTrail?.currentStageIndex == 0 else { return }
        guard treasurePreparationTask == nil else { return }
        guard treasurePreparationDayKey != dayKey else { return }
        treasurePreparationDayKey = dayKey
        let engine = tileEngine
        let resolver = landmarkResolver
        treasurePreparationTask = Task { [weak self] in
            let targets = await resolver.targets(
                near: location.coordinate,
                tileEngine: engine
            )
            guard let self else { return }
            self.treasurePreparationTask = nil
            guard !Task.isCancelled, !targets.isEmpty else { return }
            self.treasureStore.replaceTrailTargets(targets)
        }
    }

    func showMatchingFrontierLeaderboard() {
        gameCenterManager.showFrontierLeaderboard()
    }

    private func syncRecorderSettings() {
        recorder.updateSettings(
            ActivitySettings(
                maxHorizontalAccuracy: ActivitySettings.default.maxHorizontalAccuracy,
                minSampleDistance: ActivitySettings.default.minSampleDistance
            )
        )
    }

    private func handleSample(_ sample: LocationSample) {
        liveRoute.append(sample.coordinate)
        let engine = tileEngine

        if let previous = recorder.samples.dropLast().last {
            let line = TileEngine.hexLine(
                from: engine.axialCoordinate(for: previous.coordinate),
                to: engine.axialCoordinate(for: sample.coordinate)
            )
            let ids = line.map {
                TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: engine.tileSizeMeters)
            }
            processTileIDs(ids, at: sample.timestamp, activity: recorder.activityType)
        } else {
            processTileIDs(
                [engine.tileID(for: sample.coordinate)],
                at: sample.timestamp,
                activity: recorder.activityType
            )
        }
    }

    private func handleAutomaticSample(_ sample: LocationSample) {
        guard recorder.automaticExplorationEnabled, !recorder.isRecording else { return }
        explorationMode = .automatic
        store.applyWeeklyChargeResetIfNeeded()
        let engine = tileEngine
        let ids: [String]
        if let previous = automaticPreviousSample {
            ids = engine.tileIDsCoveringRoute([previous, sample])
        } else {
            ids = [engine.tileID(for: sample.coordinate)]
        }
        automaticPreviousSample = sample
        processAutomaticTileIDs(ids, at: sample.timestamp)
        prepareTreasureTrail()
    }

    private func processAutomaticTileIDs(_ ids: [String], at date: Date) {
        let newIDs = ids.filter { automaticVisitedTileIDs.insert($0).inserted }
        guard !newIDs.isEmpty else { return }
        if automaticVisitedTileIDs.count > 500 {
            automaticVisitedTileIDs = Set(newIDs)
        }

        var updated = store.tiles
        let discoveryCandidates = Set(newIDs.filter {
            updated[$0]?.isDiscovered != true
        })
        let progress = progression.processVisits(
            tileIDs: newIDs,
            tiles: &updated,
            tileEngine: tileEngine,
            at: date,
            activity: .unknown
        )
        let modified = inventoryStore.applyXPModifiers(
            discovery: progress.discoveryXP,
            familiarity: progress.familiarityXP
        )
        let territoryFamiliarity = territoryEngine.modifiedFamiliarityXP(
            base: modified.familiarity,
            tileIDs: newIDs,
            state: store.territoryState,
            tileEngine: tileEngine
        )
        store.applyLiveVisitProgress(
            updatedTiles: newIDs.compactMap { updated[$0] },
            discoveryXP: modified.discovery,
            familiarityXP: territoryFamiliarity
        )
        treasureStore.processVisitedTileIDs(newIDs)
        let territoryForFinds = store.territoryState
        let findTileEngine = tileEngine
        inventoryStore.processVisitedTileIDs(
            newIDs,
            discoveryTileIDs: discoveryCandidates,
            date: date,
            findChanceBonus: { tileID in
                TerritoryEngine().findChanceBonusPercent(
                    forTileID: tileID,
                    state: territoryForFinds,
                    tileEngine: findTileEngine
                )
            }
        )
        objectWillChange.send()
        processFrontierScoring(newDiscoveryIDs: Array(discoveryCandidates), at: date)
        if progress.tilesDiscovered > 0 {
            regionLookup.resolve(tiles: store.discoveredTiles)
        }
    }

    private func processTileIDs(_ ids: [String], at date: Date, activity: ActivityType) {
        let engine = tileEngine
        var newIDs: [String] = []
        for id in ids where sessionVisitedTileIDs.insert(id).inserted {
            newIDs.append(id)
        }
        guard !newIDs.isEmpty else { return }

        for id in newIDs where sessionTiles[id] == nil {
            sessionTiles[id] = store.tiles[id]
        }

        let priorStates: [String: TileState] = Dictionary(
            uniqueKeysWithValues: newIDs.map { id in
                (id, sessionTiles[id]?.state ?? .fogged)
            }
        )

        let discoveryCandidates = Set(newIDs.filter { id in
            guard let tile = sessionTiles[id] else { return true }
            return tile.state == .fogged || tile.firstVisitedAt == nil
        })

        let progress = progression.processVisits(
            tileIDs: newIDs,
            tiles: &sessionTiles,
            tileEngine: engine,
            at: date,
            activity: activity
        )

        let modified = inventoryStore.applyXPModifiers(
            discovery: progress.discoveryXP,
            familiarity: progress.familiarityXP
        )
        let territoryFamiliarity = territoryEngine.modifiedFamiliarityXP(
            base: modified.familiarity,
            tileIDs: newIDs,
            state: store.territoryState,
            tileEngine: tileEngine
        )

        var discovered = sessionDiscoveredIDs
        for id in discoveryCandidates {
            if let tile = sessionTiles[id], tile.isDiscovered {
                discovered.insert(id)
            }
        }
        sessionDiscoveredIDs = discovered

        sessionProgress.tilesVisited = sessionVisitedTileIDs.count
        sessionProgress.tilesDiscovered += progress.tilesDiscovered
        sessionProgress.tilesRevisited += progress.tilesRevisited
        sessionProgress.discoveryXP += modified.discovery
        sessionProgress.familiarityXP += territoryFamiliarity
        sessionDiscoveredCount = sessionProgress.tilesDiscovered

        emitSessionFeedback(
            discoveredCount: progress.tilesDiscovered,
            tileIDs: newIDs,
            priorStates: priorStates,
            at: date
        )

        treasureStore.processVisitedTileIDs(newIDs)
        let territoryForFinds = store.territoryState
        let findTileEngine = tileEngine
        inventoryStore.processVisitedTileIDs(
            newIDs,
            discoveryTileIDs: discoveryCandidates,
            date: date,
            findChanceBonus: { tileID in
                TerritoryEngine().findChanceBonusPercent(
                    forTileID: tileID,
                    state: territoryForFinds,
                    tileEngine: findTileEngine
                )
            }
        )
        objectWillChange.send()
        processFrontierScoring(newDiscoveryIDs: Array(discoveryCandidates), at: date)

        let discoveredUpdates = newIDs.compactMap { id -> WorldTile? in
            guard let tile = sessionTiles[id], tile.isDiscovered else { return nil }
            return tile
        }
        store.applyLiveVisitProgress(
            updatedTiles: discoveredUpdates,
            discoveryXP: modified.discovery,
            familiarityXP: territoryFamiliarity
        )
    }

    private func processFrontierScoring(newDiscoveryIDs: [String], at date: Date) {
        guard !newDiscoveryIDs.isEmpty else { return }

        let discovered = frontierEngine.discoveredTileCoordinates(from: mergedTiles)
        let territory = frontierEngine.territoryAnchor(
            playerTile: playerTileCoordinate,
            discovered: discovered
        )
        let activeOffer = store.frontierState.activeOffer
        var connectionBonuses = Set(store.frontierState.connectionBonusesAwarded)
        var targetCount = activeOffer.map {
            frontierEngine.targetSectorDiscoveredCount(offer: $0, tiles: mergedTiles, tileEngine: tileEngine)
        } ?? 0

        var batchTilePoints = 0
        var batchConnectionBonus = 0
        var batchCompletionBonus = 0
        var completedOffer: ExpeditionOffer?
        var newCalloutIDs: [UUID] = []
        var chargedTiles: [WorldTile] = []

        for id in newDiscoveryIDs {
            guard let coordinate = tileEngine.parseTileID(id) else { continue }
            guard let tile = sessionTiles[id] ?? store.tiles[id], tile.isDiscovered else { continue }
            guard !scoredFrontierTiles.contains(id) else { continue }

            let isNew = tile.visitCount <= 1
            let result = frontierEngine.scoreDiscovery(
                tileID: id,
                tile: coordinate,
                isNewDiscovery: isNew,
                activeOffer: activeOffer,
                territory: territory,
                discovered: discovered,
                targetSectorDiscoveredCount: targetCount,
                connectionBonusesAwarded: connectionBonuses,
                combo: frontierCombo,
                tileEngine: tileEngine,
                at: date
            )

            frontierCombo = result.combo
            guard let award = result.award else { continue }

            let scaledPoints = award.totalPoints

            scoredFrontierTiles.insert(id)
            batchTilePoints += scaledPoints
            sessionFrontier.comboPeak = max(sessionFrontier.comboPeak, award.comboMultiplier)

            if let offer = activeOffer,
               sectorEngine.sectorID(for: coordinate, sizeMeters: tileEngine.tileSizeMeters) == offer.targetSectorID {
                targetCount += 1
                sessionFrontier.targetTilesDiscovered = targetCount
                sessionFrontier.targetTilesRequired = offer.tilesRequired
            }

            if result.connectionBonusAwarded, let bonus = award.connectionBonus, let offer = activeOffer {
                connectionBonuses.insert(offer.id)
                batchConnectionBonus += bonus
                sessionFrontier.didConnectTarget = true
            }

            if let completion = result.completionBonus, let offer = activeOffer {
                batchCompletionBonus += completion
                completedOffer = offer
            }

            var updatedTile = tile
            updatedTile.weeklyCharge = min(FrontierConstants.maxWeeklyCharge, updatedTile.weeklyCharge + 1)
            if explorationMode.isExplicitSession {
                sessionTiles[id] = updatedTile
            }
            chargedTiles.append(updatedTile)

            let calloutID = UUID()
            newCalloutIDs.append(calloutID)
            frontierScoreCallouts.append(
                FrontierScoreCallout(id: calloutID, tileID: id, points: scaledPoints, createdAt: date)
            )
        }

        if !newCalloutIDs.isEmpty {
            pruneFrontierCallouts(after: newCalloutIDs)
            AtlasHaptics.light()
        }

        guard batchTilePoints > 0 || batchConnectionBonus > 0 || batchCompletionBonus > 0 else { return }

        sessionFrontier.tilePoints += batchTilePoints
        sessionFrontier.connectionBonus += batchConnectionBonus
        sessionFrontier.completionBonus += batchCompletionBonus
        sessionFrontierScore += batchTilePoints + batchConnectionBonus + batchCompletionBonus

        store.updateFrontierState({ state in
            var next = state
            next.weeklyScore += batchTilePoints + batchConnectionBonus + batchCompletionBonus
            next.connectionBonusesAwarded = Array(Set(next.connectionBonusesAwarded).union(connectionBonuses))
            for tile in chargedTiles where tile.weeklyCharge > 0 {
                if !next.chargedTileIDs.contains(tile.id) {
                    next.chargedTileIDs.append(tile.id)
                }
            }
            if let completedOffer {
                if !next.completedOfferIDs.contains(completedOffer.id) {
                    next.completedOfferIDs.append(completedOffer.id)
                    next.lifetimeCompletedExpeditions += 1
                }
                next.activeOfferID = nil
            }
            return next
        }, playerTile: playerTileCoordinate, updatedTiles: chargedTiles)

        sessionFrontier.weeklyTotalAfter = store.frontierState.weeklyScore
    }

    private func emitSessionFeedback(
        discoveredCount: Int,
        tileIDs: [String],
        priorStates: [String: TileState],
        at date: Date
    ) {
        var events: [SessionFeedbackEvent] = []

        if discoveredCount > 0 {
            events.append(SessionFeedbackEvent(kind: .discovery(count: discoveredCount), createdAt: date))
            AtlasHaptics.discovery()
        }

        var masteryUps: [TileState] = []
        for id in tileIDs {
            let prior = priorStates[id] ?? .fogged
            guard let next = sessionTiles[id]?.state else { continue }
            guard next.rawValue > prior.rawValue, next.rawValue >= TileState.explored.rawValue else { continue }
            masteryUps.append(next)
        }

        if let highest = masteryUps.max(by: { $0.rawValue < $1.rawValue }) {
            events.append(SessionFeedbackEvent(kind: .mastery(state: highest), createdAt: date))
            AtlasHaptics.mastery()
        }

        guard !events.isEmpty else { return }
        sessionFeedback.append(contentsOf: events)
        pruneSessionFeedback(after: events.map(\.id))
    }

    private func pruneSessionFeedback(after ids: [UUID]) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            sessionFeedback.removeAll { ids.contains($0.id) }
        }
    }

    private func pruneFrontierCallouts(after ids: [UUID]) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            frontierScoreCallouts.removeAll { ids.contains($0.id) }
        }
    }
}

#if DEBUG
extension WorldController {
    static let debugDefaultCoordinate = CLLocationCoordinate2D(latitude: 51.8133, longitude: 4.6901)

    enum DebugStepSize: Double, CaseIterable, Identifiable {
        case fine = 25
        case tile = 55
        case leap = 120

        var id: Double { rawValue }

        var label: String {
            switch self {
            case .fine: "Fine"
            case .tile: "55 m"
            case .leap: "120 m"
            }
        }
    }

    func debugEnableSimulation(seedIfNeeded: Bool = true) {
        recorder.setSimulationActive(true)
        if seedIfNeeded, recorder.lastLocation == nil {
            debugTeleport(to: Self.debugDefaultCoordinate)
        }
    }

    func debugDisableSimulation() {
        recorder.setSimulationActive(false)
    }

    func debugTeleport(to coordinate: CLLocationCoordinate2D, course: CLLocationDirection = 0, speed: CLLocationSpeed = 0) {
        recorder.setSimulationActive(true)
        recorder.ingestSimulatedLocation(
            Self.debugLocation(coordinate: coordinate, course: course, speed: speed)
        )
        refreshFrontierPresentation()
    }

    func debugNudge(northMeters: Double, eastMeters: Double, speed: CLLocationSpeed = 1.4) {
        recorder.setSimulationActive(true)
        let base = recorder.lastLocation?.coordinate ?? Self.debugDefaultCoordinate
        let next = Self.offset(base, northMeters: northMeters, eastMeters: eastMeters)
        let course = Self.courseDegrees(northMeters: northMeters, eastMeters: eastMeters)
        recorder.ingestSimulatedLocation(
            Self.debugLocation(coordinate: next, course: course, speed: speed)
        )
    }

    func debugNudge(headingDegrees: Double, distanceMeters: Double, speed: CLLocationSpeed = 1.4) {
        let radians = headingDegrees * .pi / 180
        let north = cos(radians) * distanceMeters
        let east = sin(radians) * distanceMeters
        debugNudge(northMeters: north, eastMeters: east, speed: speed)
    }

    private static func debugLocation(
        coordinate: CLLocationCoordinate2D,
        course: CLLocationDirection,
        speed: CLLocationSpeed
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: -1,
            course: course,
            speed: max(0, speed),
            timestamp: Date()
        )
    }

    private static func offset(
        _ coordinate: CLLocationCoordinate2D,
        northMeters: Double,
        eastMeters: Double
    ) -> CLLocationCoordinate2D {
        let earth = 6_378_137.0
        let dLat = (northMeters / earth) * (180 / .pi)
        let cosLat = cos(coordinate.latitude * .pi / 180)
        let dLon = cosLat == 0 ? 0 : (eastMeters / (earth * cosLat)) * (180 / .pi)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + dLat,
            longitude: coordinate.longitude + dLon
        )
    }

    private static func courseDegrees(northMeters: Double, eastMeters: Double) -> CLLocationDirection {
        guard northMeters != 0 || eastMeters != 0 else { return 0 }
        var degrees = atan2(eastMeters, northMeters) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }
}
#endif
