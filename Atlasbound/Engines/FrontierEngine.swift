import Foundation

/// Frontier territory detection, weekly expedition generation, and scoring.
struct FrontierEngine: Sendable {
    let sectorEngine = HexSectorEngine()

    static let baseTilePoints = 10
    static let targetSectorBonus = 15
    static let connectionBonus = 250
    static let maxSectorDiscoveryFraction = 0.10
    static let comboWindow: TimeInterval = 20 * 60

    // MARK: - ISO week

    static func isoWeekKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return String(format: "%d-W%02d", year, week)
    }

    // MARK: - Territory

    func discoveredTileCoordinates(from tiles: [String: WorldTile]) -> Set<TileCoordinate> {
        Set(tiles.values.filter(\.isDiscovered).map(\.coordinate))
    }

    func connectedComponents(from discovered: Set<TileCoordinate>) -> [[TileCoordinate]] {
        guard !discovered.isEmpty else { return [] }
        var remaining = discovered
        var components: [[TileCoordinate]] = []

        while let seed = remaining.first {
            var queue = [seed]
            var component: [TileCoordinate] = []
            remaining.remove(seed)

            while let current = queue.popLast() {
                component.append(current)
                for neighbor in axialNeighbors(of: current) where remaining.contains(neighbor) {
                    remaining.remove(neighbor)
                    queue.append(neighbor)
                }
            }
            components.append(component)
        }
        return components
    }

    func territoryAnchor(
        playerTile: TileCoordinate?,
        discovered: Set<TileCoordinate>
    ) -> Set<TileCoordinate> {
        let components = connectedComponents(from: discovered)
        guard !components.isEmpty else {
            if let playerTile {
                return [playerTile]
            }
            return []
        }
        guard let playerTile else {
            return Set(components.max(by: { $0.count < $1.count }) ?? [])
        }
        let nearest = components.min { lhs, rhs in
            let lDist = lhs.map { TileEngine.hexDistance($0, playerTile) }.min() ?? .max
            let rDist = rhs.map { TileEngine.hexDistance($0, playerTile) }.min() ?? .max
            if lDist != rDist { return lDist < rDist }
            return lhs.count > rhs.count
        }
        return Set(nearest ?? components[0])
    }

    func frontierTileCoordinates(
        territory: Set<TileCoordinate>,
        discovered: Set<TileCoordinate>
    ) -> Set<TileCoordinate> {
        var frontier: Set<TileCoordinate> = []
        for tile in territory {
            for neighbor in axialNeighbors(of: tile) where !discovered.contains(neighbor) {
                frontier.insert(neighbor)
            }
        }
        return frontier
    }

    func isConnectedToTerritory(
        tile: TileCoordinate,
        territory: Set<TileCoordinate>,
        discovered: Set<TileCoordinate>
    ) -> Bool {
        guard discovered.contains(tile) else { return false }
        if territory.contains(tile) { return true }
        return axialNeighbors(of: tile).contains(where: territory.contains)
    }

    func routeConnectsTerritoryToSector(
        territory: Set<TileCoordinate>,
        discovered: Set<TileCoordinate>,
        targetSectorID: String,
        tileEngine: TileEngine
    ) -> Bool {
        guard let parsed = sectorEngine.parseSectorID(targetSectorID) else { return false }
        let targetSector = parsed.sector
        let targetTiles = sectorEngine.tiles(in: targetSector)
        let connectedDiscovered = discovered.filter { tile in
            isConnectedToTerritory(tile: tile, territory: territory, discovered: discovered)
        }
        return !connectedDiscovered.isDisjoint(with: targetTiles)
    }

    // MARK: - Weekly offers

    func ensureWeeklyState(
        state: FrontierState,
        playerTile: TileCoordinate?,
        discoveredTileIDs: Set<String>,
        tiles: [String: WorldTile],
        tileEngine: TileEngine,
        installationID: String,
        date: Date = .now
    ) -> FrontierState {
        let weekKey = Self.isoWeekKey(for: date)
        var next = state
        if next.weekKey != weekKey {
            if next.weeklyScore > next.bestWeekScore {
                next.bestWeekScore = next.weeklyScore
            }
            next.weekKey = weekKey
            next.offers = []
            next.activeOfferID = nil
            next.completedOfferIDs = []
            next.weeklyScore = 0
            next.connectionBonusesAwarded = []
            next.chargedTileIDs = []
        }
        if next.offers.isEmpty {
            next.offers = generateWeeklyOffers(
                playerTile: playerTile,
                discoveredTileIDs: discoveredTileIDs,
                tiles: tiles,
                tileEngine: tileEngine,
                installationID: installationID,
                weekKey: weekKey
            )
        }
        return next
    }

    func generateWeeklyOffers(
        playerTile: TileCoordinate?,
        discoveredTileIDs: Set<String>,
        tiles: [String: WorldTile],
        tileEngine: TileEngine,
        installationID: String,
        weekKey: String
    ) -> [ExpeditionOffer] {
        let discovered = discoveredTileCoordinates(from: tiles)
        let anchorTile = playerTile ?? discovered.first ?? TileCoordinate(q: 0, r: 0)
        let anchorSector = sectorEngine.sectorCoordinate(for: anchorTile)
        let territory = territoryAnchor(playerTile: playerTile, discovered: discovered)
        let seed = weeklySeed(weekKey: weekKey, sizeMeters: tileEngine.tileSizeMeters, installationID: installationID)

        var offers: [ExpeditionOffer] = []
        var usedSectors: Set<String> = []
        var usedDirections: Set<Int> = []

        for difficulty in ExpeditionDifficulty.allCases {
            let direction = pickDirection(
                seed: seed,
                difficulty: difficulty,
                anchorSector: anchorSector,
                usedDirections: usedDirections
            )
            usedDirections.insert(direction)

            if let offer = makeOffer(
                difficulty: difficulty,
                anchorSector: anchorSector,
                directionIndex: direction,
                discoveredTileIDs: discoveredTileIDs,
                tileEngine: tileEngine,
                weekKey: weekKey,
                installationID: installationID,
                usedSectors: &usedSectors,
                territory: territory,
                discovered: discovered
            ) {
                offers.append(offer)
            }
        }
        return offers
    }

    // MARK: - Scoring

    func advanceCombo(
        current: FrontierComboState,
        qualifyingTile: Bool,
        at date: Date
    ) -> FrontierComboState {
        var combo = current
        if let expires = combo.expiresAt, expires <= date {
            combo = .empty
        }
        guard qualifyingTile else { return combo }
        combo.count += 1
        combo.expiresAt = date.addingTimeInterval(Self.comboWindow)
        return combo
    }

    func scoreDiscovery(
        tileID: String,
        tile: TileCoordinate,
        isNewDiscovery: Bool,
        activeOffer: ExpeditionOffer?,
        territory: Set<TileCoordinate>,
        discovered: Set<TileCoordinate>,
        targetSectorDiscoveredCount: Int,
        connectionBonusesAwarded: Set<String>,
        combo: FrontierComboState,
        tileEngine: TileEngine,
        at date: Date
    ) -> (award: FrontierTileAward?, combo: FrontierComboState, connectionBonusAwarded: Bool, completionBonus: Int?) {
        guard isNewDiscovery else {
            return (nil, combo, false, nil)
        }
        guard isConnectedToTerritory(tile: tile, territory: territory, discovered: discovered) else {
            return (nil, combo, false, nil)
        }

        var nextCombo = advanceCombo(current: combo, qualifyingTile: true, at: date)
        let multiplier = nextCombo.multiplier

        var base = Self.baseTilePoints
        var sectorBonus = 0
        if let offer = activeOffer,
           let parsed = sectorEngine.parseSectorID(offer.targetSectorID),
           sectorEngine.sectorCoordinate(for: tile) == parsed.sector {
            sectorBonus = Self.targetSectorBonus
        }

        let subtotal = base + sectorBonus
        let total = Int((Double(subtotal) * multiplier).rounded())

        var connectionAwarded = false
        var connectionBonusValue: Int?
        if let offer = activeOffer,
           !connectionBonusesAwarded.contains(offer.id) {
            var extendedDiscovered = discovered
            extendedDiscovered.insert(tile)
            if routeConnectsTerritoryToSector(
                territory: territory,
                discovered: extendedDiscovered,
                targetSectorID: offer.targetSectorID,
                tileEngine: tileEngine
            ) {
                connectionAwarded = true
                connectionBonusValue = Self.connectionBonus
            }
        }

        var completionBonus: Int?
        if let offer = activeOffer {
            let inTarget = sectorEngine.sectorID(for: tile, sizeMeters: tileEngine.tileSizeMeters) == offer.targetSectorID
            let newCount = targetSectorDiscoveredCount + (inTarget ? 1 : 0)
            if newCount >= offer.tilesRequired {
                completionBonus = offer.completionBonus
            }
        }

        let award = FrontierTileAward(
            tileID: tileID,
            basePoints: base,
            sectorBonus: sectorBonus,
            comboMultiplier: multiplier,
            totalPoints: total,
            connectionBonus: connectionBonusValue
        )
        return (award, nextCombo, connectionAwarded, completionBonus)
    }

    func targetSectorDiscoveredCount(
        offer: ExpeditionOffer,
        tiles: [String: WorldTile],
        tileEngine: TileEngine
    ) -> Int {
        guard let parsed = sectorEngine.parseSectorID(offer.targetSectorID) else { return 0 }
        let members = sectorEngine.tiles(in: parsed.sector)
        return members.filter { tile in
            let id = TileEngine.makeTileID(q: tile.q, r: tile.r, sizeMeters: tileEngine.tileSizeMeters)
            return tiles[id]?.isDiscovered == true
        }.count
    }

    // MARK: - Private

    private func weeklySeed(weekKey: String, sizeMeters: Double, installationID: String) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(weekKey)
        hasher.combine(Int(sizeMeters.rounded()))
        hasher.combine(installationID)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private func pickDirection(
        seed: UInt64,
        difficulty: ExpeditionDifficulty,
        anchorSector: SectorCoordinate,
        usedDirections: Set<Int>
    ) -> Int {
        let base = Int((seed &+ UInt64(difficulty.sectorDistance * 17) &+ UInt64(anchorSector.q &* 13) &+ UInt64(anchorSector.r &* 7)) % 6)
        if !usedDirections.contains(base) { return base }
        for offset in 1..<6 {
            let candidate = (base + offset) % 6
            if !usedDirections.contains(candidate) { return candidate }
        }
        return base
    }

    private func makeOffer(
        difficulty: ExpeditionDifficulty,
        anchorSector: SectorCoordinate,
        directionIndex: Int,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine,
        weekKey: String,
        installationID: String,
        usedSectors: inout Set<String>,
        territory: Set<TileCoordinate>,
        discovered: Set<TileCoordinate>
    ) -> ExpeditionOffer? {
        var distance = difficulty.sectorDistance
        let maxDistance = difficulty.sectorDistance + 4
        while distance <= maxDistance {
            let sector = sectorEngine.sectorAt(distance: distance, from: anchorSector, directionIndex: directionIndex)
            let sectorID = sectorEngine.sectorID(for: sector, sizeMeters: tileEngine.tileSizeMeters)
            if usedSectors.contains(sectorID) {
                distance += 1
                continue
            }
            let fraction = sectorEngine.completionFraction(
                sector: sector,
                discoveredTileIDs: discoveredTileIDs,
                tileEngine: tileEngine
            )
            if fraction > Self.maxSectorDiscoveryFraction {
                distance += 1
                continue
            }
            usedSectors.insert(sectorID)
            let id = offerID(
                weekKey: weekKey,
                installationID: installationID,
                difficulty: difficulty,
                directionIndex: directionIndex,
                sectorID: sectorID
            )
            return ExpeditionOffer(
                id: id,
                difficulty: difficulty,
                targetSectorID: sectorID,
                targetSectorDistance: distance,
                directionIndex: directionIndex,
                tilesRequired: difficulty.tilesRequired,
                completionBonus: difficulty.completionBonus
            )
        }
        return nil
    }

    private func offerID(
        weekKey: String,
        installationID: String,
        difficulty: ExpeditionDifficulty,
        directionIndex: Int,
        sectorID: String
    ) -> String {
        var hasher = Hasher()
        hasher.combine(weekKey)
        hasher.combine(installationID)
        hasher.combine(difficulty.rawValue)
        hasher.combine(directionIndex)
        hasher.combine(sectorID)
        return "expedition:\(abs(hasher.finalize()))"
    }

    private func axialNeighbors(of tile: TileCoordinate) -> [TileCoordinate] {
        [
            TileCoordinate(q: tile.q + 1, r: tile.r),
            TileCoordinate(q: tile.q + 1, r: tile.r - 1),
            TileCoordinate(q: tile.q, r: tile.r - 1),
            TileCoordinate(q: tile.q - 1, r: tile.r),
            TileCoordinate(q: tile.q - 1, r: tile.r + 1),
            TileCoordinate(q: tile.q, r: tile.r + 1),
        ]
    }
}
