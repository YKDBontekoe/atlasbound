import Foundation

/// Awards discovery XP on first visit; familiarity/mastery XP on revisits (diminishing).
struct ProgressionEngine: Sendable {
    static let discoveryXP: Int = 100

    /// Base familiarity XP before diminishing returns.
    static let baseFamiliarityXP: Int = 25
    static let familiarityXPFloor: Int = 5
    /// Diminishing revisit awards after discovery (index 0 = first revisit).
    static let familiarityXPTable: [Int] = [baseFamiliarityXP, 20, 16, 12, 10]

    static let exploredMasteryXP: Int = 150
    static let surveyedMasteryXP: Int = 200
    static let masteredMasteryXP: Int = 300
    static let legendaryMasteryXP: Int = 500

    func processVisit(
        tile: inout WorldTile,
        at date: Date = .now,
        activity: ActivityType = .unknown,
        modifiers: SkillModifiers = .identity
    ) -> VisitResult {
        tile.activityStamps.insert(activity)

        if tile.state == .fogged || tile.firstVisitedAt == nil {
            return applyDiscovery(&tile, at: date, modifiers: modifiers)
        } else {
            return applyFamiliarity(&tile, at: date, modifiers: modifiers)
        }
    }

    func processVisits(
        tileIDs: [String],
        tiles: inout [String: WorldTile],
        tileEngine: TileEngine,
        at date: Date = .now,
        activity: ActivityType = .unknown,
        modifiers: SkillModifiers = .identity
    ) -> SessionProgress {
        var discoveryXP = 0
        var familiarityXP = 0
        var discovered = 0
        var revisited = 0

        var processed = 0
        for id in tileIDs {
            guard let coordinate = tileEngine.parseTileID(id) else { continue }
            var tile = tiles[id] ?? WorldTile(id: id, coordinate: coordinate)
            guard tile.id == id, tile.coordinate == coordinate else { continue }
            let result = processVisit(tile: &tile, at: date, activity: activity, modifiers: modifiers)
            tiles[id] = tile
            processed += 1

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
            tilesVisited: processed,
            tilesDiscovered: discovered,
            tilesRevisited: revisited,
            discoveryXP: discoveryXP,
            familiarityXP: familiarityXP
        )
    }

    // MARK: - Private

    private func applyDiscovery(
        _ tile: inout WorldTile,
        at date: Date,
        modifiers: SkillModifiers
    ) -> VisitResult {
        let xp = scaleXP(Self.discoveryXP, by: modifiers.discoveryXPMultiplier)
        tile.state = .discovered
        tile.masteryXP += xp
        tile.visitCount = max(tile.visitCount, 0) + 1
        tile.firstVisitedAt = date
        tile.lastVisitedAt = date
        tile.uniqueVisitDays = 1
        advanceStateIfNeeded(&tile, modifiers: modifiers)
        return VisitResult(kind: .discovery, xpAwarded: xp, tileID: tile.id)
    }

    private func applyFamiliarity(
        _ tile: inout WorldTile,
        at date: Date,
        modifiers: SkillModifiers
    ) -> VisitResult {
        let base = familiarityXP(forVisitCount: tile.visitCount)
        let xp = scaleXP(base, by: modifiers.familiarityXPMultiplier)
        tile.masteryXP += xp
        tile.visitCount += 1

        let calendar = Calendar.current
        if let previous = tile.lastVisitedAt, !calendar.isDate(previous, inSameDayAs: date) {
            tile.uniqueVisitDays += 1
        }
        tile.lastVisitedAt = date

        advanceStateIfNeeded(&tile, modifiers: modifiers)

        return VisitResult(kind: .familiarity, xpAwarded: xp, tileID: tile.id)
    }

    /// Diminishing familiarity from `familiarityXPTable`, then `familiarityXPFloor`.
    /// `existingVisits` is the visit count before this revisit (at least 1 after discovery).
    func familiarityXP(forVisitCount existingVisits: Int) -> Int {
        let revisitIndex = max(existingVisits, 1)
        let table = Self.familiarityXPTable
        if revisitIndex - 1 < table.count {
            return table[revisitIndex - 1]
        }
        return Self.familiarityXPFloor
    }

    /// Effective mastery thresholds after Surveying skills (never rewrite stored masteryXP).
    func effectiveThreshold(_ base: Int, modifiers: SkillModifiers) -> Int {
        let scaled = Double(base) * max(0.75, modifiers.masteryThresholdMultiplier)
        return max(1, Int(scaled.rounded()))
    }

    private func advanceStateIfNeeded(_ tile: inout WorldTile, modifiers: SkillModifiers = .identity) {
        let legendary = effectiveThreshold(Self.legendaryMasteryXP, modifiers: modifiers)
        let mastered = effectiveThreshold(Self.masteredMasteryXP, modifiers: modifiers)
        let surveyed = effectiveThreshold(Self.surveyedMasteryXP, modifiers: modifiers)
        let explored = effectiveThreshold(Self.exploredMasteryXP, modifiers: modifiers)

        switch tile.masteryXP {
        case legendary...:
            if tile.state.rawValue < TileState.legendary.rawValue { tile.state = .legendary }
        case mastered..<legendary:
            if tile.state.rawValue < TileState.mastered.rawValue { tile.state = .mastered }
        case surveyed..<mastered:
            if tile.state.rawValue < TileState.surveyed.rawValue { tile.state = .surveyed }
        case explored..<surveyed:
            if tile.state.rawValue < TileState.explored.rawValue { tile.state = .explored }
        default:
            break
        }
    }

    /// Survey Beacon / tools: add mastery XP and advance state without counting a visit.
    func applyMasteryPulse(
        tile: inout WorldTile,
        amount: Int,
        modifiers: SkillModifiers = .identity
    ) {
        guard amount > 0, tile.isDiscovered else { return }
        let scaled = scaleXP(amount, by: modifiers.masteryPulseMultiplier)
        tile.masteryXP += scaled
        advanceStateIfNeeded(&tile, modifiers: modifiers)
    }

    private func scaleXP(_ base: Int, by multiplier: Double) -> Int {
        max(base, Int((Double(base) * max(1, multiplier)).rounded()))
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
