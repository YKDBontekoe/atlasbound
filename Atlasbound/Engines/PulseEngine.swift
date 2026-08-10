import Foundation

/// Pure rules for the living-world layer. It never performs persistence or I/O.
struct PulseEngine: Sendable {
    static let interactionRangeTiles = 4
    static let maximumActivePulses = 3
    static let pulseSlotHours = 6
    static let pulseCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private let kinds: [PulseKind] = [.signalDrift, .fogFront, .resourceBloom]

    func localPulses(
        around anchor: TileCoordinate,
        tileEngine: TileEngine,
        at date: Date,
        existing: [AtlasPulse] = []
    ) -> [AtlasPulse] {
        let calendar = Self.pulseCalendar
        let hour = calendar.component(.hour, from: date)
        let slot = hour / Self.pulseSlotHours
        let dayKey = DateFormatter.pulseDayKey.string(from: date)
        let slotSeed = StableHash.fnv1a64("pulse:\(dayKey):\(slot):\(anchor.q):\(anchor.r)")
        let candidates = tileEngine.ring(around: anchor, radius: 7)
            .filter { TileEngine.hexDistance(anchor, $0) >= 3 }
            .sorted { lhs, rhs in
                StableHash.fnv1a64("\(slotSeed):\(lhs.q):\(lhs.r)")
                    < StableHash.fnv1a64("\(slotSeed):\(rhs.q):\(rhs.r)")
            }

        let start = calendar.startOfDay(for: date)
        let slotStart = calendar.date(byAdding: .hour, value: slot * Self.pulseSlotHours, to: start) ?? date
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        return kinds.enumerated().compactMap { index, kind in
            guard let coordinate = candidates.dropFirst(index * 3).first else { return nil }
            let tileID = TileEngine.makeTileID(q: coordinate.q, r: coordinate.r, sizeMeters: tileEngine.tileSizeMeters)
            let seed = StableHash.fnv1a64("pulse:\(dayKey):\(slot):\(index):\(tileID)")
            let id = "pulse:\(dayKey):\(slot):\(index):\(tileID)"
            if let current = existingByID[id] {
                return current.refreshed(at: date)
            }

            let developing = slotStart.addingTimeInterval(2 * 60 * 60)
            let peak = slotStart.addingTimeInterval(4 * 60 * 60)
            let expires = slotStart.addingTimeInterval(6 * 60 * 60)
            return AtlasPulse(
                id: id,
                kind: kind,
                anchorTileID: tileID,
                startedAt: slotStart,
                phaseEndsAt: [.developing: developing, .peak: peak],
                expiresAt: expires,
                seed: seed,
                phase: date < developing ? .detected : (date < peak ? .developing : .peak),
                resolvedAction: nil
            )
        }
    }

    func rankedPulses(
        _ pulses: [AtlasPulse],
        playerTile: TileCoordinate?,
        tileEngine: TileEngine,
        at date: Date
    ) -> [AtlasPulse] {
        pulses
            .map { $0.refreshed(at: date) }
            .filter { $0.phase != .resolved && $0.expiresAt > date }
            .sorted { lhs, rhs in
                score(lhs, playerTile: playerTile, tileEngine: tileEngine, at: date)
                    > score(rhs, playerTile: playerTile, tileEngine: tileEngine, at: date)
            }
    }

    func score(
        _ pulse: AtlasPulse,
        playerTile: TileCoordinate?,
        tileEngine: TileEngine,
        at date: Date
    ) -> Double {
        let distance: Int
        if let playerTile, let pulseTile = tileEngine.parseTileID(pulse.anchorTileID) {
            distance = TileEngine.hexDistance(playerTile, pulseTile)
        } else {
            distance = 99
        }
        let phaseScore: Double = switch pulse.phase(at: date) {
        case .detected: 1.0
        case .developing: 2.0
        case .peak: 4.0
        case .resolved: -100
        }
        return phaseScore * 100 - Double(distance) * 4
    }

    func canInteract(
        _ pulse: AtlasPulse,
        playerTile: TileCoordinate?,
        tileEngine: TileEngine,
        at date: Date
    ) -> Bool {
        guard pulse.phase(at: date) != .resolved,
              pulse.expiresAt > date,
              pulse.resolvedAction == nil,
              let playerTile,
              let pulseTile = tileEngine.parseTileID(pulse.anchorTileID)
        else { return false }
        return TileEngine.hexDistance(playerTile, pulseTile) <= Self.interactionRangeTiles
    }

    func outcome(for pulse: AtlasPulse, action: PulseAction) -> PulseOutcome {
        switch (pulse.kind, action) {
        case (.signalDrift, .observe):
            PulseOutcome(title: "Signal recorded", detail: "The drift is now part of your atlas notes.", rewardItemID: "survey_ink", rewardQuantity: 1, claimCondition: .watched)
        case (.signalDrift, .stabilize):
            PulseOutcome(title: "Signal steadied", detail: "A nearby sector settles into an awake rhythm.", rewardItemID: "compass_filament", rewardQuantity: 1, claimCondition: .awake)
        case (.signalDrift, .harvest):
            PulseOutcome(title: "Signal harvested", detail: "You caught the useful resonance before it moved on.", rewardItemID: "waystone_shard", rewardQuantity: 1, claimCondition: nil)
        case (.fogFront, .observe):
            PulseOutcome(title: "Fog pattern recorded", detail: "The clearing reveals a route-shaped echo.", rewardItemID: "fog_lint", rewardQuantity: 1, claimCondition: .awake)
        case (.fogFront, .stabilize):
            PulseOutcome(title: "Fogline softened", detail: "The nearby atlas should remain easier to read for a while.", rewardItemID: "survey_ink", rewardQuantity: 1, claimCondition: .awake)
        case (.fogFront, .harvest):
            PulseOutcome(title: "Fog gathered", detail: "You collected a small piece of the passing front.", rewardItemID: "fog_lint", rewardQuantity: 2, claimCondition: nil)
        case (.resourceBloom, .observe):
            PulseOutcome(title: "Bloom mapped", detail: "The bright seam is now marked in your field notes.", rewardItemID: "survey_ink", rewardQuantity: 1, claimCondition: .charged)
        case (.resourceBloom, .stabilize):
            PulseOutcome(title: "Bloom anchored", detail: "The sector keeps its charged condition for the next cycle.", rewardItemID: "amber_resin", rewardQuantity: 1, claimCondition: .charged)
        case (.resourceBloom, .harvest):
            PulseOutcome(title: "Bloom harvested", detail: "You gathered the richest part before the seam dimmed.", rewardItemID: "copper_ore", rewardQuantity: 2, claimCondition: nil)
        default:
            PulseOutcome(title: "Echo recorded", detail: "The atlas remembers that you were here.", rewardItemID: "survey_ink", rewardQuantity: 1, claimCondition: nil)
        }
    }

    func condition(for pulse: AtlasPulse, action: PulseAction, at date: Date) -> ClaimConditionState? {
        let outcome = outcome(for: pulse, action: action)
        guard let condition = outcome.claimCondition else { return nil }
        return ClaimConditionState(
            condition: condition,
            effectiveFrom: date,
            effectiveUntil: date.addingTimeInterval(24 * 60 * 60),
            sourcePulseID: pulse.id
        )
    }
}

private extension DateFormatter {
    static let pulseDayKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = PulseEngine.pulseCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = PulseEngine.pulseCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
