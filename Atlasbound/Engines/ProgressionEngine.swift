import Foundation

/// Awards discovery XP on first visit; familiarity/mastery XP on revisits (diminishing).
struct ProgressionEngine: Sendable {
    static let discoveryXP: Int = 100

    /// Base familiarity XP before diminishing returns.
    static let baseFamiliarityXP: Int = 25

    func processVisit(
        tile: inout WorldTile,
        at date: Date = .now,
        activity: ActivityType = .unknown
    ) -> VisitResult {
        tile.activityStamps.insert(activity)

        if tile.state == .fogged || tile.firstVisitedAt == nil {
            return applyDiscovery(&tile, at: date)
        } else {
            return applyFamiliarity(&tile, at: date)
        }
    }

    func processVisits(
        tileIDs: [String],
        tiles: inout [String: WorldTile],
        tileEngine: TileEngine,
        at date: Date = .now,
        activity: ActivityType = .unknown
    ) -> SessionProgress {
        var discoveryXP = 0
        var familiarityXP = 0
        var discovered = 0
        var revisited = 0

        for id in tileIDs {
            var tile = tiles[id] ?? makeTile(id: id, engine: tileEngine)
            let result = processVisit(tile: &tile, at: date, activity: activity)
            tiles[id] = tile

            switch result.kind {
            case .discovery:
                discovered += 1
                discoveryXP += result.xpAwarded
            case .familiarity:
                revisited += 1
                familiarityXP += result.xpAwarded
            }
        }

        return SessionProgress(
            tilesVisited: tileIDs.count,
            tilesDiscovered: discovered,
            tilesRevisited: revisited,
            discoveryXP: discoveryXP,
            familiarityXP: familiarityXP
        )
    }

    // MARK: - Private

    private func applyDiscovery(_ tile: inout WorldTile, at date: Date) -> VisitResult {
        tile.state = .discovered
        tile.masteryXP += Self.discoveryXP
        tile.visitCount = max(tile.visitCount, 0) + 1
        tile.firstVisitedAt = date
        tile.lastVisitedAt = date
        tile.uniqueVisitDays = 1
        return VisitResult(kind: .discovery, xpAwarded: Self.discoveryXP, tileID: tile.id)
    }

    private func applyFamiliarity(_ tile: inout WorldTile, at date: Date) -> VisitResult {
        let xp = familiarityXP(forVisitCount: tile.visitCount)
        tile.masteryXP += xp
        tile.visitCount += 1

        let calendar = Calendar.current
        if let previous = tile.lastVisitedAt, !calendar.isDate(previous, inSameDayAs: date) {
            tile.uniqueVisitDays += 1
        }
        tile.lastVisitedAt = date

        advanceStateIfNeeded(&tile)

        return VisitResult(kind: .familiarity, xpAwarded: xp, tileID: tile.id)
    }

    /// Diminishing familiarity: 25, 20, 16, 12, 10, then floor of 5.
    /// `existingVisits` is the visit count before this revisit (at least 1 after discovery).
    func familiarityXP(forVisitCount existingVisits: Int) -> Int {
        let revisitIndex = max(existingVisits, 1)
        let table = [25, 20, 16, 12, 10]
        if revisitIndex - 1 < table.count {
            return table[revisitIndex - 1]
        }
        return 5
    }

    private func advanceStateIfNeeded(_ tile: inout WorldTile) {
        // Lightweight thresholds for Phase 1 — full skill tree later.
        switch tile.masteryXP {
        case 500...:
            if tile.state.rawValue < TileState.legendary.rawValue { tile.state = .legendary }
        case 300..<500:
            if tile.state.rawValue < TileState.mastered.rawValue { tile.state = .mastered }
        case 200..<300:
            if tile.state.rawValue < TileState.surveyed.rawValue { tile.state = .surveyed }
        case 150..<200:
            if tile.state.rawValue < TileState.explored.rawValue { tile.state = .explored }
        default:
            break
        }
    }

    private func makeTile(id: String, engine: TileEngine) -> WorldTile {
        let coordinate = engine.parseTileID(id) ?? TileCoordinate(q: 0, r: 0)
        return WorldTile(id: id, coordinate: coordinate)
    }
}

enum VisitKind: Sendable {
    case discovery
    case familiarity
}

struct VisitResult: Sendable {
    let kind: VisitKind
    let xpAwarded: Int
    let tileID: String
}

struct SessionProgress: Sendable {
    var tilesVisited: Int
    var tilesDiscovered: Int
    var tilesRevisited: Int
    var discoveryXP: Int
    var familiarityXP: Int

    static let empty = SessionProgress(
        tilesVisited: 0,
        tilesDiscovered: 0,
        tilesRevisited: 0,
        discoveryXP: 0,
        familiarityXP: 0
    )
}
