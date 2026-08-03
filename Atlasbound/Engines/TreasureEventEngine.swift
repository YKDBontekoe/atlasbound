import Foundation

struct TreasureEventEngine: Sendable {
    static func localDayKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func isoWeekKey(for date: Date = .now, calendar: Calendar? = nil) -> String {
        var resolvedCalendar = calendar ?? Calendar(identifier: .iso8601)
        if calendar == nil {
            resolvedCalendar.timeZone = .current
        }
        let parts = resolvedCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    func makeFallbackTrail(
        anchor: TileCoordinate,
        tileEngine: TileEngine,
        dayKey: String
    ) -> TreasureTrail {
        let seed = StableHash.fnv1a64(dayKey)
        let radii = TreasureConstants.fallbackRingRadii
        let candidates = (0..<(TreasureConstants.stagesPerTrail * 2)).map { index -> LandmarkTarget in
            let radius = radii[index % radii.count]
            let direction = Int((seed + UInt64(index * 5)) % 6)
            let coordinate = DistanceLootEngine.tileAtRadius(
                around: anchor,
                radius: radius,
                direction: direction
            )
            let tileID = TileEngine.makeTileID(
                q: coordinate.q,
                r: coordinate.r,
                sizeMeters: tileEngine.tileSizeMeters
            )
            let distanceMeters = DistanceLootEngine.meters(
                hexDistance: radius,
                tileSizeMeters: tileEngine.tileSizeMeters
            )
            return LandmarkTarget(
                id: "fallback:\(dayKey):\(index)",
                tileID: tileID,
                name: "Mysterious Cache",
                category: "Hidden landmark",
                clue: "Follow the compass toward a distant edge of your atlas.",
                isFallback: true,
                distanceMeters: distanceMeters
            )
        }
        return makeTrail(dayKey: dayKey, targets: candidates)
    }

    func makeTrail(dayKey: String, targets: [LandmarkTarget]) -> TreasureTrail {
        precondition(!targets.isEmpty)
        let padded = (0..<(TreasureConstants.stagesPerTrail * 2)).map { targets[$0 % targets.count] }
        let stages = (0..<TreasureConstants.stagesPerTrail).map { index in
            TreasureStage(
                id: "trail:\(dayKey):stage:\(index)",
                directTarget: padded[index],
                detourTarget: padded[index + TreasureConstants.stagesPerTrail],
                selectedChoice: nil,
                isCompleted: false
            )
        }
        return TreasureTrail(
            id: "trail:\(dayKey)",
            dayKey: dayKey,
            stages: stages,
            currentStageIndex: 0,
            isCompleted: false,
            freeRerollsRemaining: 1
        )
    }

    func makeVaultTarget(
        anchor: TileCoordinate,
        tileEngine: TileEngine,
        weekKey: String
    ) -> LandmarkTarget {
        let radius = TreasureConstants.vaultRingRadius
        let seed = StableHash.fnv1a64(weekKey)
        let index = Int(seed % UInt64(max(1, 6 * radius)))
        let coordinate = DistanceLootEngine.tileOnRing(around: anchor, radius: radius, index: index)
        let distanceMeters = DistanceLootEngine.meters(
            hexDistance: TileEngine.hexDistance(anchor, coordinate),
            tileSizeMeters: tileEngine.tileSizeMeters
        )
        return LandmarkTarget(
            id: "vault:\(weekKey)",
            tileID: TileEngine.makeTileID(q: coordinate.q, r: coordinate.r, sizeMeters: tileEngine.tileSizeMeters),
            name: "Weekly Atlas Vault",
            category: "Vault",
            clue: "Three trail keys have revealed a vault on a distant frontier.",
            isFallback: true,
            distanceMeters: distanceMeters
        )
    }

    func relic(
        seed: String,
        landmarkName: String,
        choice: TreasureChoice,
        isVault: Bool,
        distanceMeters: Double = 0,
        date: Date = .now
    ) -> RelicRecord {
        let value = StableHash.fnv1a64(seed)
        let theme = RelicTheme.allCases[Int(value % UInt64(RelicTheme.allCases.count))]
        let band = DistanceLootEngine.band(meters: distanceMeters)
        let roll = max(0, Int((value / 7) % 100) - DistanceLootEngine.rarityRollBonus(for: band))
        let rarity: RelicRarity
        if isVault {
            rarity = roll < 20 ? .legendary : .rare
        } else if choice == .detour {
            rarity = roll < 5 ? .legendary : (roll < 45 ? .rare : .uncommon)
        } else {
            rarity = roll < 5 ? .rare : (roll < 30 ? .uncommon : .common)
        }
        let relicIndex = Int((value / 13) % 6) + 1
        return RelicRecord(
            id: UUID(),
            relicID: "\(theme.rawValue)-\(relicIndex)",
            name: "\(rarity.displayName) \(theme.displayName) Relic \(relicIndex)",
            theme: theme,
            rarity: rarity,
            landmarkName: landmarkName,
            discoveredAt: date,
            source: isVault ? "Weekly Vault" : "Daily Trail"
        )
    }

    func completionFamiliarityXP(isVault: Bool, distanceMeters: Double) -> Int {
        let band = DistanceLootEngine.band(meters: distanceMeters)
        return isVault
            ? DistanceLootEngine.vaultCompletionXP(for: band)
            : DistanceLootEngine.trailCompletionXP(for: band)
    }
}
