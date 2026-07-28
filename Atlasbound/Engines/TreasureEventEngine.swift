import Foundation

struct TreasureEventEngine: Sendable {
    static func localDayKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func isoWeekKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    func makeFallbackTrail(
        anchor: TileCoordinate,
        tileEngine: TileEngine,
        dayKey: String
    ) -> TreasureTrail {
        let seed = stableSeed(dayKey)
        let candidates = (0..<(TreasureConstants.stagesPerTrail * 2)).map { index -> LandmarkTarget in
            let radius = 5 + index * 3
            let direction = Int((seed + UInt64(index * 5)) % 6)
            let ring = tileEngine.ring(around: anchor, radius: radius)
            let coordinate = ring.isEmpty ? anchor : ring[direction * max(1, ring.count / 6) % ring.count]
            let tileID = TileEngine.makeTileID(
                q: coordinate.q,
                r: coordinate.r,
                sizeMeters: tileEngine.tileSizeMeters
            )
            return LandmarkTarget(
                id: "fallback:\(dayKey):\(index)",
                tileID: tileID,
                name: "Mysterious Cache",
                category: "Hidden landmark",
                clue: "Follow the compass to an undiscovered edge of your atlas.",
                isFallback: true
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
        let ring = tileEngine.ring(around: anchor, radius: 12)
        let index = ring.isEmpty ? 0 : Int(stableSeed(weekKey) % UInt64(ring.count))
        let coordinate = ring.isEmpty ? anchor : ring[index]
        return LandmarkTarget(
            id: "vault:\(weekKey)",
            tileID: TileEngine.makeTileID(q: coordinate.q, r: coordinate.r, sizeMeters: tileEngine.tileSizeMeters),
            name: "Weekly Atlas Vault",
            category: "Vault",
            clue: "Three trail keys have revealed a vault near your frontier.",
            isFallback: true
        )
    }

    func relic(
        seed: String,
        landmarkName: String,
        choice: TreasureChoice,
        isVault: Bool,
        date: Date = .now
    ) -> RelicRecord {
        let value = stableSeed(seed)
        let theme = RelicTheme.allCases[Int(value % UInt64(RelicTheme.allCases.count))]
        let rarity: RelicRarity
        let roll = Int((value / 7) % 100)
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

    private func stableSeed(_ string: String) -> UInt64 {
        string.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
