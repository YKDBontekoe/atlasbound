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

    let recorder: ActivityRecorder
    let store: TileStore
    let activityHistory: ActivityHistoryStore
    let regionLookup: RegionLookupStore
    let gameCenterManager: GameCenterManager
    private let progression = ProgressionEngine()
    private let frontierEngine = FrontierEngine()
    private let worldEventEngine = WorldEventEngine()
    private let sectorEngine = HexSectorEngine()

    /// Tiles mutated during the active session (merged into store on stop).
    private var sessionTiles: [String: WorldTile] = [:]
    private var sessionProgress = SessionProgress.empty
    private var sessionFrontier = FrontierSessionContribution.empty
    private var scoredFrontierTiles: Set<String> = []
    private var scoredWorldEventTiles: Set<String> = []

    private static let selectedActivityKey = "atlasbound.selectedActivityType"

    init(
        store: TileStore,
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore? = nil,
        gameCenterManager: GameCenterManager? = nil,
        recorder: ActivityRecorder? = nil
    ) {
        self.store = store
        self.activityHistory = activityHistory
        self.regionLookup = regionLookup ?? RegionLookupStore()
        self.gameCenterManager = gameCenterManager ?? GameCenterManager()
        self.recorder = recorder ?? ActivityRecorder()
        restoreSelectedActivityType()
        syncRecorderSettings()

        self.recorder.onSample = { [weak self] sample in
            self?.handleSample(sample)
        }
        syncTileSizeToActivity()
        refreshFrontierPresentation()
        refreshWorldEventPresentation()
    }

    var isRecording: Bool { recorder.isRecording }
    var isPaused: Bool { recorder.isPaused }

    var tileEngine: TileEngine { store.tileEngine }

    var frontierState: FrontierState { store.frontierState }

    var activeExpedition: ExpeditionOffer? { store.frontierState.activeOffer }

    var availableExpeditions: [ExpeditionOffer] { store.frontierState.availableOffers }

    var weeklyFrontierScore: Int { store.frontierState.weeklyScore }

    var worldEventState: WorldEventState { store.worldEventState }

    var liveWorldEvent: WorldEventInstance? {
        worldEventEngine.liveEvent(from: store.worldEventState)
    }

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

    var currentGridLabel: String { store.tileSize.label }

    var discoveredTileCount: Int { store.discoveredTiles.count }

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

    var eventBeaconCoordinate: CLLocationCoordinate2D? {
        guard let event = liveWorldEvent else { return nil }
        if let sectorID = event.targetSectorID,
           let parsed = sectorEngine.parseSectorID(sectorID) {
            let center = sectorEngine.centerTile(for: parsed.sector)
            return tileEngine.centerCoordinate(for: center)
        }
        // For hotspot circuits, point at the first unvisited hotspot.
        let visited = store.worldEventState.visitedHotspotSet
        let hotspotID = event.hotspotTileIDs.first { !visited.contains($0) }
            ?? event.hotspotTileIDs.first
            ?? store.worldEventState.dailyHotspotTileIDs.first
        guard let hotspotID, let axial = tileEngine.parseTileID(hotspotID) else { return nil }
        return tileEngine.centerCoordinate(for: axial)
    }

    var eventSectorBoundaryTileIDs: Set<String> {
        guard let event = liveWorldEvent,
              let sectorID = event.targetSectorID,
              let parsed = sectorEngine.parseSectorID(sectorID) else {
            return []
        }
        return Set(sectorEngine.boundaryTiles(for: parsed.sector).map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: tileEngine.tileSizeMeters)
        })
    }

    var eventHighlightTileIDs: Set<String> {
        guard let event = liveWorldEvent,
              let sectorID = event.targetSectorID,
              let parsed = sectorEngine.parseSectorID(sectorID) else {
            return []
        }
        // Soft wash: sample a subset of sector members for overlay budget.
        let members = Array(sectorEngine.tiles(in: parsed.sector))
        let discovered = store.discoveredTileIDs
        return Set(members.prefix(80).compactMap { tile -> String? in
            let id = TileEngine.makeTileID(q: tile.q, r: tile.r, sizeMeters: tileEngine.tileSizeMeters)
            return discovered.contains(id) ? nil : id
        })
    }

    var mapHotspots: [MapHotspot] {
        let state = store.worldEventState
        let eventTargets = Set(liveWorldEvent?.hotspotTileIDs ?? [])
        let visited = state.visitedHotspotSet
        let ids = state.dailyHotspotTileIDs.isEmpty
            ? Array(eventTargets)
            : state.dailyHotspotTileIDs
        return ids.prefix(WorldEventConstants.maxVisibleHotspots).map { tileID in
            MapHotspot(
                id: tileID,
                tileID: tileID,
                isVisited: visited.contains(tileID),
                isEventTarget: eventTargets.contains(tileID) || liveWorldEvent?.kind == .hotspotCircuit
            )
        }
    }

    var placeMapPins: [PlaceMapPin] {
        let labels = regionLookup.successfulLabels
        var pins: [PlaceMapPin] = []
        for (cellKey, place) in labels {
            guard let name = place.locality ?? place.administrativeArea else { continue }
            guard let coordinate = RegionLookupEngine.representativeCoordinate(forCellKey: cellKey) else { continue }
            pins.append(
                PlaceMapPin(
                    id: cellKey,
                    name: name,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            )
            if pins.count >= WorldEventConstants.maxPlacePins { break }
        }
        return pins.sorted { $0.name < $1.name }
    }

    var worldEventProgressLabel: String {
        guard let event = store.worldEventState.activeEvent else { return "" }
        let progress = worldEventEngine.progressToward(active: event, state: store.worldEventState)
        if event.tilesRequired > 0 {
            return "\(min(progress, event.tilesRequired))/\(event.tilesRequired)"
        }
        return event.kind.displayName
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
        return engine.ring(around: center, radius: radius).filter { axial in
            let id = TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: engine.tileSizeMeters)
            let tile = store.tiles[id] ?? sessionTiles[id]
            return tile == nil || tile?.state == .fogged
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
        recorder.startMonitoringIfNeeded()
        syncTileSizeToActivity()
        store.applyWeeklyChargeResetIfNeeded()
        refreshFrontierPresentation()
        refreshWorldEventPresentation()
        gameCenterManager.authenticate()
    }

    func setActivityType(_ type: ActivityType) {
        guard !recorder.isRecording else { return }
        guard type != .unknown else { return }
        recorder.activityType = type
        UserDefaults.standard.set(type.rawValue, forKey: Self.selectedActivityKey)
        syncTileSizeToActivity()
        refreshFrontierPresentation()
        refreshWorldEventPresentation()
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

    private func restoreSelectedActivityType() {
        guard let raw = UserDefaults.standard.string(forKey: Self.selectedActivityKey),
              let type = ActivityType(rawValue: raw),
              type != .unknown else {
            return
        }
        recorder.activityType = type
    }

    func startActivity() {
        syncTileSizeToActivity()
        store.applyWeeklyChargeResetIfNeeded()
        refreshFrontierPresentation()
        refreshWorldEventPresentation()
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
        scoredWorldEventTiles = []
        if let offer = activeExpedition {
            sessionFrontier.targetTilesRequired = offer.tilesRequired
            sessionFrontier.targetTilesDiscovered = targetSectorDiscoveredCount
        }
        lastSummary = nil
        AtlasHaptics.prepare()
        recorder.start()
    }

    private func syncTileSizeToActivity() {
        let option = recorder.activityType.tileSize
        guard store.tileSize != option else {
            syncRecorderSettings()
            return
        }
        store.tileSize = option
        syncRecorderSettings()
    }

    func pauseActivity() {
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

        let engine = tileEngine
        let covering = engine.tileIDsCoveringRoute(result.samples)
        processTileIDs(covering, at: result.endedAt, activity: recorder.activityType)

        store.applySessionProgress(sessionProgress, updatedTiles: sessionTiles)

        sessionFrontier.weeklyTotalAfter = store.frontierState.weeklyScore

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
            frontierContribution: sessionFrontier
        )
        activityHistory.record(summary, tileSizeMeters: store.tileSize.rawValue)
        lastSummary = summary
        frontierCombo = .empty
        frontierScoreCallouts = []
        regionLookup.resolve(tilesBySize: store.allDiscoveredTilesBySize)

        Task {
            await gameCenterManager.submitFrontierScore(
                store.frontierState.weeklyScore,
                tileSize: store.tileSize
            )
        }
    }

    func refreshFrontierPresentation() {
        store.refreshFrontierState(playerTile: playerTileCoordinate)
    }

    func refreshWorldEventPresentation() {
        store.refreshWorldEventState(playerTile: playerTileCoordinate)
    }

    func showMatchingFrontierLeaderboard() {
        gameCenterManager.showFrontierLeaderboard(tileSize: store.tileSize)
    }

    private func syncRecorderSettings() {
        recorder.updateSettings(
            ActivitySettings(
                tileSize: store.tileSize,
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

        let liveEvent = worldEventEngine.liveEvent(from: store.worldEventState, at: date)
        let multipliers = worldEventEngine.xpMultipliers(for: liveEvent)
        let boostedDiscoveryXP = Int((Double(progress.discoveryXP) * multipliers.discovery).rounded())
        let boostedFamiliarityXP = Int((Double(progress.familiarityXP) * multipliers.familiarity).rounded())

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
        sessionProgress.discoveryXP += boostedDiscoveryXP
        sessionProgress.familiarityXP += boostedFamiliarityXP
        sessionDiscoveredCount = sessionProgress.tilesDiscovered

        emitSessionFeedback(
            discoveredCount: progress.tilesDiscovered,
            tileIDs: newIDs,
            priorStates: priorStates,
            at: date
        )

        processWorldEventScoring(visitedIDs: newIDs, discoveryCandidateIDs: Array(discoveryCandidates), at: date)
        processFrontierScoring(newDiscoveryIDs: Array(discoveryCandidates), at: date)

        let discoveredUpdates = newIDs.compactMap { id -> WorldTile? in
            guard let tile = sessionTiles[id], tile.isDiscovered else { return nil }
            return tile
        }
        store.applyLiveVisitProgress(
            updatedTiles: discoveredUpdates,
            discoveryXP: boostedDiscoveryXP,
            familiarityXP: boostedFamiliarityXP
        )
    }

    private func processWorldEventScoring(visitedIDs: [String], discoveryCandidateIDs: [String], at date: Date) {
        guard !visitedIDs.isEmpty else { return }
        let discoverySet = Set(discoveryCandidateIDs)
        var bonusFamiliarity = 0
        var feedbackEvents: [SessionFeedbackEvent] = []

        store.updateWorldEventState({ state in
            var next = state
            for id in visitedIDs {
                guard !scoredWorldEventTiles.contains(id) else { continue }
                guard let coordinate = tileEngine.parseTileID(id) else { continue }
                let isNew = discoverySet.contains(id)
                let result = worldEventEngine.processVisit(
                    tileID: id,
                    tile: coordinate,
                    isNewDiscovery: isNew,
                    state: next,
                    at: date,
                    tileEngine: tileEngine
                )
                next = result.state
                scoredWorldEventTiles.insert(id)
                guard let award = result.award else { continue }
                bonusFamiliarity += award.familiarityXPBonus
                if award.didComplete {
                    feedbackEvents.append(
                        SessionFeedbackEvent(
                            kind: .worldEvent(title: award.kind.displayName, detail: "Event complete"),
                            createdAt: date
                        )
                    )
                } else if award.wasHotspotVisit {
                    feedbackEvents.append(SessionFeedbackEvent(kind: .hotspot, createdAt: date))
                }
            }
            return next
        }, playerTile: playerTileCoordinate)

        if bonusFamiliarity > 0 {
            sessionProgress.familiarityXP += bonusFamiliarity
            store.addXP(discovery: 0, familiarity: bonusFamiliarity)
        }

        if !feedbackEvents.isEmpty {
            // Keep toasts light — show at most one event toast per batch.
            let toast = feedbackEvents.last!
            sessionFeedback.append(toast)
            pruneSessionFeedback(after: [toast.id])
            AtlasHaptics.light()
        }
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

        for id in newDiscoveryIDs {
            guard let coordinate = tileEngine.parseTileID(id) else { continue }
            guard let tile = sessionTiles[id], tile.isDiscovered else { continue }
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

            let liveEvent = worldEventEngine.liveEvent(from: store.worldEventState, at: date)
            let eventMultiplier = worldEventEngine.frontierScoreMultiplier(for: liveEvent)
            let scaledPoints = Int((Double(award.totalPoints) * eventMultiplier).rounded())

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
            var chargeGain = 1
            if liveEvent?.kind == .frontierCharge {
                chargeGain += WorldEventConstants.frontierChargeBonus
            }
            updatedTile.weeklyCharge = min(FrontierConstants.maxWeeklyCharge, updatedTile.weeklyCharge + chargeGain)
            sessionTiles[id] = updatedTile

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
            for id in sessionTiles.keys {
                if let tile = sessionTiles[id], tile.weeklyCharge > 0, !next.chargedTileIDs.contains(id) {
                    next.chargedTileIDs.append(id)
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
        }, playerTile: playerTileCoordinate)

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
            case .fine: "25 m"
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
