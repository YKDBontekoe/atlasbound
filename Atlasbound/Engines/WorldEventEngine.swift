import Foundation

/// Client-scheduled world events, daily hotspot generation, and visit scoring.
struct WorldEventEngine: Sendable {
    let sectorEngine = HexSectorEngine()

    // MARK: - Day / window keys

    static func utcDayKey(for date: Date = .now, calendar: Calendar = Self.utcCalendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func friendlyDayLabel(for dayKey: String) -> String {
        guard dayKey.count == 10 else { return "Today" }
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayKey) else { return dayKey }
        let display = DateFormatter()
        display.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return display.string(from: date)
    }

    /// Remaining window label for HUD.
    static func remainingLabel(until end: Date, now: Date = .now) -> String {
        let remaining = max(0, end.timeIntervalSince(now))
        let hours = Int(remaining) / 3_600
        let minutes = (Int(remaining) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    // MARK: - Catalog

    /// Rotating kind from UTC day-of-year so all players share the same schedule.
    static func catalogKind(for date: Date, calendar: Calendar = utcCalendar) -> WorldEventKind {
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let kinds = WorldEventKind.allCases
        return kinds[(dayOfYear - 1) % kinds.count]
    }

    /// Time window for the day's event. Destination events run all day; bonus events use evening UTC.
    static func eventWindow(
        for kind: WorldEventKind,
        on date: Date,
        calendar: Calendar = utcCalendar
    ) -> (start: Date, end: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        switch kind {
        case .beaconRush, .hotspotCircuit:
            let end = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
            return (startOfDay, end)
        case .surge, .frontierCharge:
            let start = calendar.date(byAdding: .hour, value: 14, to: startOfDay) ?? startOfDay
            let end = calendar.date(byAdding: .hour, value: 20, to: startOfDay) ?? start.addingTimeInterval(6 * 3_600)
            return (start, end)
        }
    }

    // MARK: - State refresh

    func ensureState(
        state: WorldEventState,
        playerTile: TileCoordinate?,
        discoveredTileIDs: Set<String>,
        tiles: [String: WorldTile],
        tileEngine: TileEngine,
        installationID: String,
        date: Date = .now
    ) -> WorldEventState {
        let dayKey = Self.utcDayKey(for: date)
        var next = state

        if next.dayKey != dayKey {
            next.dayKey = dayKey
            next.visitedHotspotIDs = []
            next.eventProgressCount = 0
            next.completedEventIDs = []
            next.activeEvent = nil
            next.dailyHotspotTileIDs = []
        }

        if next.dailyHotspotTileIDs.isEmpty || shouldRegenerateHotspots(
            hotspotIDs: next.dailyHotspotTileIDs,
            playerTile: playerTile,
            tileEngine: tileEngine
        ) {
            next.dailyHotspotTileIDs = generateDailyHotspots(
                playerTile: playerTile,
                discoveredTileIDs: discoveredTileIDs,
                tiles: tiles,
                tileEngine: tileEngine,
                installationID: installationID,
                dayKey: dayKey
            )
            // Reset visited markers only when the set of hotspots actually changed.
            let newSet = Set(next.dailyHotspotTileIDs)
            next.visitedHotspotIDs = next.visitedHotspotIDs.filter { newSet.contains($0) }
        }

        let kind = Self.catalogKind(for: date)
        let window = Self.eventWindow(for: kind, on: date)
        let live = date >= window.start && date < window.end

        if live {
            if next.activeEvent?.dayKey != dayKey || next.activeEvent?.kind != kind {
                next.activeEvent = makeInstance(
                    kind: kind,
                    dayKey: dayKey,
                    window: window,
                    playerTile: playerTile,
                    discoveredTileIDs: discoveredTileIDs,
                    tiles: tiles,
                    tileEngine: tileEngine,
                    installationID: installationID,
                    dailyHotspots: next.dailyHotspotTileIDs
                )
                next.eventProgressCount = 0
            } else if var active = next.activeEvent {
                // Refresh destination targets if player moved and targets were empty.
                if active.kind == .beaconRush, active.targetSectorID == nil {
                    active = makeInstance(
                        kind: kind,
                        dayKey: dayKey,
                        window: window,
                        playerTile: playerTile,
                        discoveredTileIDs: discoveredTileIDs,
                        tiles: tiles,
                        tileEngine: tileEngine,
                        installationID: installationID,
                        dailyHotspots: next.dailyHotspotTileIDs
                    )
                    next.activeEvent = active
                }
                if active.kind == .hotspotCircuit, active.hotspotTileIDs.isEmpty {
                    active.hotspotTileIDs = next.dailyHotspotTileIDs
                    next.activeEvent = active
                }
            }
        } else if let active = next.activeEvent, !active.isLive(at: date) {
            // Keep completed progress for the day sheet, but mark window closed by clearing live target sector wash via controller.
            // Retain instance for history until day roll.
        }

        return next
    }

    func makeInstance(
        kind: WorldEventKind,
        dayKey: String,
        window: (start: Date, end: Date),
        playerTile: TileCoordinate?,
        discoveredTileIDs: Set<String>,
        tiles: [String: WorldTile],
        tileEngine: TileEngine,
        installationID: String,
        dailyHotspots: [String]
    ) -> WorldEventInstance {
        let id = "event:\(dayKey):\(kind.rawValue)"
        var targetSectorID: String?
        var hotspotIDs: [String] = []
        var tilesRequired = 0
        var discoveryMult = 1.0
        var familiarityMult = 1.0
        var frontierMult = 1.0
        let title: String
        let subtitle: String

        switch kind {
        case .surge:
            title = "XP Surge"
            subtitle = "Discover and revisit tiles for boosted XP"
            discoveryMult = WorldEventConstants.surgeDiscoveryMultiplier
            familiarityMult = WorldEventConstants.surgeFamiliarityMultiplier
            tilesRequired = 8
        case .beaconRush:
            title = "Beacon Rush"
            subtitle = "Discover tiles inside the highlighted sector"
            tilesRequired = WorldEventConstants.beaconRushTilesRequired
            targetSectorID = pickBeaconSector(
                playerTile: playerTile,
                discoveredTileIDs: discoveredTileIDs,
                tiles: tiles,
                tileEngine: tileEngine,
                installationID: installationID,
                dayKey: dayKey
            )
        case .hotspotCircuit:
            title = "Hotspot Circuit"
            subtitle = "Visit today's highlighted hexes"
            hotspotIDs = dailyHotspots
            tilesRequired = min(WorldEventConstants.hotspotCircuitRequired, max(1, dailyHotspots.count))
        case .frontierCharge:
            title = "Frontier Charge"
            subtitle = "Frontier discoveries score extra and charge harder"
            frontierMult = WorldEventConstants.frontierScoreMultiplier
            tilesRequired = 6
        }

        return WorldEventInstance(
            id: id,
            kind: kind,
            dayKey: dayKey,
            title: title,
            subtitle: subtitle,
            targetSectorID: targetSectorID,
            hotspotTileIDs: hotspotIDs,
            tilesRequired: tilesRequired,
            completionFamiliarityXP: WorldEventConstants.completionFamiliarityXP,
            discoveryXPMultiplier: discoveryMult,
            familiarityXPMultiplier: familiarityMult,
            frontierScoreMultiplier: frontierMult,
            windowStart: window.start,
            windowEnd: window.end
        )
    }

    // MARK: - Hotspots

    /// Deterministic daily hotspot tile IDs near the frontier (or around the player).
    func generateDailyHotspots(
        playerTile: TileCoordinate?,
        discoveredTileIDs: Set<String>,
        tiles: [String: WorldTile],
        tileEngine: TileEngine,
        installationID: String,
        dayKey: String,
        count: Int = WorldEventConstants.dailyHotspotCount
    ) -> [String] {
        let frontierEngine = FrontierEngine()
        let discovered = frontierEngine.discoveredTileCoordinates(from: tiles)
        let territory = frontierEngine.territoryAnchor(playerTile: playerTile, discovered: discovered)
        var candidates = frontierEngine.frontierTileCoordinates(territory: territory, discovered: discovered)

        if candidates.isEmpty, let playerTile {
            candidates = Set(tileEngine.ring(around: playerTile, radius: 3).filter { axial in
                let id = TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: tileEngine.tileSizeMeters)
                return !discoveredTileIDs.contains(id)
            })
        }

        if candidates.isEmpty {
            let anchor = playerTile ?? TileCoordinate(q: 0, r: 0)
            candidates = Set(tileEngine.ring(around: anchor, radius: 2))
        }

        let seed = hotspotSeed(dayKey: dayKey, sizeMeters: tileEngine.tileSizeMeters, installationID: installationID)
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.q != rhs.q { return lhs.q < rhs.q }
            return lhs.r < rhs.r
        }

        guard !sorted.isEmpty else { return [] }

        var picks: [String] = []
        var used = Set<TileCoordinate>()
        var index = Int(seed % UInt64(sorted.count))

        for step in 0..<(count * 4) where picks.count < count {
            let candidate = sorted[(index + step * 7) % sorted.count]
            guard !used.contains(candidate) else { continue }
            // Prefer spread — skip if too close to an existing pick.
            let tooClose = used.contains { other in
                TileEngine.hexDistance(other, candidate) < 2
            }
            if tooClose && picks.count + 1 < count { continue }
            used.insert(candidate)
            let id = TileEngine.makeTileID(
                q: candidate.q,
                r: candidate.r,
                sizeMeters: tileEngine.tileSizeMeters
            )
            picks.append(id)
        }

        if picks.count < count {
            let start = Int(seed % UInt64(sorted.count))
            for step in 0..<sorted.count where picks.count < count {
                let tile = sorted[(start + step) % sorted.count]
                let id = TileEngine.makeTileID(q: tile.q, r: tile.r, sizeMeters: tileEngine.tileSizeMeters)
                if !picks.contains(id) {
                    picks.append(id)
                }
            }
        }

        return picks
    }

    // MARK: - Visit scoring

    func liveEvent(from state: WorldEventState, at date: Date = .now) -> WorldEventInstance? {
        guard let active = state.activeEvent, active.isLive(at: date) else { return nil }
        guard !state.completedEventSet.contains(active.id) else { return nil }
        return active
    }

    func processVisit(
        tileID: String,
        tile: TileCoordinate,
        isNewDiscovery: Bool,
        state: WorldEventState,
        at date: Date = .now,
        tileEngine: TileEngine
    ) -> (award: WorldEventVisitAward?, state: WorldEventState) {
        var next = state
        let wasHotspot = next.dailyHotspotTileIDs.contains(tileID) || (next.activeEvent?.hotspotTileIDs.contains(tileID) ?? false)
        if wasHotspot, !next.visitedHotspotIDs.contains(tileID) {
            next.visitedHotspotIDs.append(tileID)
        }

        guard let active = liveEvent(from: next, at: date) else {
            if wasHotspot {
                return (
                    WorldEventVisitAward(
                        tileID: tileID,
                        kind: .hotspotCircuit,
                        progressDelta: 0,
                        familiarityXPBonus: 0,
                        didComplete: false,
                        wasHotspotVisit: true
                    ),
                    next
                )
            }
            return (nil, next)
        }

        var progressDelta = 0
        switch active.kind {
        case .hotspotCircuit:
            if active.hotspotTileIDs.contains(tileID) {
                progressDelta = 1
            }
        case .beaconRush:
            if let sectorID = active.targetSectorID,
               sectorEngine.sectorID(for: tile, sizeMeters: tileEngine.tileSizeMeters) == sectorID,
               isNewDiscovery {
                progressDelta = 1
                next.eventProgressCount += 1
            }
        case .surge, .frontierCharge:
            // Any visit during the window advances soft progress toward the completion bonus.
            progressDelta = 1
            next.eventProgressCount += 1
        }

        guard progressDelta > 0 || wasHotspot else {
            return (nil, next)
        }

        let progress = progressToward(active: active, state: next)
        let alreadyComplete = next.completedEventSet.contains(active.id)
        var didComplete = false
        var bonus = 0
        if !alreadyComplete, active.tilesRequired > 0, progress >= active.tilesRequired {
            didComplete = true
            bonus = active.completionFamiliarityXP
            next.completedEventIDs.append(active.id)
            next.lifetimeEventsCompleted += 1
        }

        let award = WorldEventVisitAward(
            tileID: tileID,
            kind: active.kind,
            progressDelta: progressDelta,
            familiarityXPBonus: bonus,
            didComplete: didComplete,
            wasHotspotVisit: wasHotspot
        )
        return (award, next)
    }

    func progressToward(active: WorldEventInstance, state: WorldEventState) -> Int {
        switch active.kind {
        case .hotspotCircuit:
            return state.visitedHotspotIDs.filter { active.hotspotTileIDs.contains($0) }.count
        case .beaconRush, .surge, .frontierCharge:
            return state.eventProgressCount
        }
    }

    func xpMultipliers(for event: WorldEventInstance?) -> (discovery: Double, familiarity: Double) {
        guard let event else { return (1, 1) }
        return (event.discoveryXPMultiplier, event.familiarityXPMultiplier)
    }

    func frontierScoreMultiplier(for event: WorldEventInstance?) -> Double {
        event?.frontierScoreMultiplier ?? 1.0
    }

    // MARK: - Private

    private func pickBeaconSector(
        playerTile: TileCoordinate?,
        discoveredTileIDs: Set<String>,
        tiles: [String: WorldTile],
        tileEngine: TileEngine,
        installationID: String,
        dayKey: String
    ) -> String? {
        let frontierEngine = FrontierEngine()
        let discovered = frontierEngine.discoveredTileCoordinates(from: tiles)
        let anchorTile = playerTile ?? discovered.first ?? TileCoordinate(q: 0, r: 0)
        let anchorSector = sectorEngine.sectorCoordinate(for: anchorTile)
        let seed = hotspotSeed(dayKey: dayKey, sizeMeters: tileEngine.tileSizeMeters, installationID: installationID)
        let direction = Int(seed % 6)

        for distance in 1...3 {
            let sector = sectorEngine.sectorAt(distance: distance, from: anchorSector, directionIndex: direction)
            let fraction = sectorEngine.completionFraction(
                sector: sector,
                discoveredTileIDs: discoveredTileIDs,
                tileEngine: tileEngine
            )
            if fraction < 0.35 {
                return sectorEngine.sectorID(for: sector, sizeMeters: tileEngine.tileSizeMeters)
            }
        }
        let fallback = sectorEngine.sectorAt(distance: 1, from: anchorSector, directionIndex: direction)
        return sectorEngine.sectorID(for: fallback, sizeMeters: tileEngine.tileSizeMeters)
    }

    private func hotspotSeed(dayKey: String, sizeMeters: Double, installationID: String) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(dayKey)
        hasher.combine(Int(sizeMeters.rounded()))
        hasher.combine(installationID)
        hasher.combine("hotspots")
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    /// Hotspots generated before GPS arrived can sit at the origin — refresh when the player is far from all of them.
    private func shouldRegenerateHotspots(
        hotspotIDs: [String],
        playerTile: TileCoordinate?,
        tileEngine: TileEngine
    ) -> Bool {
        guard let playerTile, !hotspotIDs.isEmpty else { return false }
        let distances = hotspotIDs.compactMap { id -> Int? in
            guard let axial = tileEngine.parseTileID(id) else { return nil }
            return TileEngine.hexDistance(axial, playerTile)
        }
        guard !distances.isEmpty else { return true }
        return distances.allSatisfy { $0 > 40 }
    }
}
