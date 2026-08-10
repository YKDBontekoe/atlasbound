import Foundation
import Combine

/// Local cache and interaction history for Atlas Pulse.
/// Server-backed Pulse state can replace the cache later without changing the UI API.
@MainActor
final class PulseStore: ObservableObject {
    @Published private(set) var state: PulseState

    private let database: AtlasDatabase
    private let engine = PulseEngine()

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil, now: Date = .now) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL))
        } else {
            self.database = .shared
        }

        state = Self.sanitized(self.database.loadPulseState() ?? .empty(at: now), now: now)
        if self.database.loadPulseState() == nil {
            self.database.savePulseState(state)
        }
    }

    private static func sqliteURL(from fileURL: URL) -> URL {
        fileURL.pathExtension.lowercased() == "json"
            ? fileURL.deletingPathExtension().appendingPathExtension("sqlite")
            : fileURL
    }

    var activePulses: [AtlasPulse] {
        let interacted = Set(state.interactions.map(\.pulseID))
        return state.activePulses.filter { $0.phase != .resolved && !interacted.contains($0.id) }
    }
    var reports: [ScoutReport] { state.reports }
    var scoutStance: ScoutStance { state.scoutStance }
    var claimConditions: [String: ClaimConditionState] { state.claimConditions }
    var pendingRewardGrants: [PulseRewardGrant] { state.pendingRewardGrants }

    func refresh(
        around playerTile: TileCoordinate,
        tileEngine: TileEngine,
        at date: Date = .now
    ) {
        let interacted = Set(state.interactions.map(\.pulseID))
        let local = engine.localPulses(
            around: playerTile,
            tileEngine: tileEngine,
            at: date,
            existing: state.activePulses
        ).filter { !interacted.contains($0.id) }
        var next = state
        next.activePulses = engine.rankedPulses(
            local + state.activePulses.filter { pulse in
                !interacted.contains(pulse.id) && !local.contains(where: { $0.id == pulse.id })
            },
            playerTile: playerTile,
            tileEngine: tileEngine,
            at: date
        ).prefix(PulseEngine.maximumActivePulses).map { $0 }
        next.lastRefreshAt = date
        replaceState(next)
    }

    func advance(at date: Date = .now) {
        var next = state
        next.activePulses = state.activePulses.map { $0.refreshed(at: date) }
            .filter { $0.phase != .resolved || $0.resolvedAction != nil }
        next.claimConditions = state.claimConditions.filter { $0.value.effectiveUntil > date }
        next.reports = Array(state.reports.suffix(20))
        replaceState(next)
    }

    @discardableResult
    func perform(
        pulseID: String,
        action: PulseAction,
        playerTile: TileCoordinate?,
        tileEngine: TileEngine,
        at date: Date = .now
    ) -> PulseActionResult {
        guard let playerTile,
              let index = state.activePulses.firstIndex(where: { $0.id == pulseID }) else {
            return .denied("That signal is no longer in your cached atlas.")
        }
        let pulse = state.activePulses[index].refreshed(at: date)
        guard engine.canInteract(pulse, playerTile: playerTile, tileEngine: tileEngine, at: date) else {
            return .denied("Move closer to interact with this Pulse.")
        }
        guard !state.interactions.contains(where: { $0.pulseID == pulseID }) else {
            return .denied("You already resolved this Pulse.")
        }

        let outcome = engine.outcome(for: pulse, action: action)
        let interaction = PulseInteraction(
            id: "interaction:\(pulseID)",
            pulseID: pulseID,
            action: action,
            createdAt: date,
            outcome: outcome
        )
        var next = state
        next.interactions.append(interaction)
        if let itemID = outcome.rewardItemID, outcome.rewardQuantity > 0 {
            next.pendingRewardGrants.append(
                PulseRewardGrant(
                    id: "pulse-reward:\(pulseID)",
                    pulseID: pulseID,
                    itemID: itemID,
                    quantity: outcome.rewardQuantity,
                    createdAt: date
                )
            )
        }
        if let condition = engine.condition(for: pulse, action: action, at: date),
           let sectorID = tileEngine.parseTileID(pulse.anchorTileID).map({ HexSectorEngine().sectorID(for: $0, sizeMeters: tileEngine.tileSizeMeters) }) {
            next.claimConditions[sectorID] = condition
        }
        replaceState(next)
        return .completed(interaction)
    }

    func markRewardGranted(_ grantID: String) {
        guard state.pendingRewardGrants.contains(where: { $0.id == grantID }) else { return }
        var next = state
        next.pendingRewardGrants.removeAll { $0.id == grantID }
        replaceState(next)
    }

    func complete(pulseID: String) {
        guard let interaction = state.interactions.first(where: { $0.pulseID == pulseID }),
              let index = state.activePulses.firstIndex(where: { $0.id == pulseID }) else { return }
        var next = state
        var pulse = next.activePulses[index]
        pulse.resolvedAction = interaction.action
        pulse.phase = .resolved
        next.activePulses[index] = pulse
        replaceState(next)
    }

    func setScoutStance(_ stance: ScoutStance) {
        guard stance != state.scoutStance else { return }
        var next = state
        next.scoutStance = stance
        replaceState(next)
    }

    func addScoutReport(_ report: ScoutReport) {
        var next = state
        next.reports = Array((state.reports + [report]).suffix(20))
        replaceState(next)
    }

    func makeBriefing(at date: Date = .now) -> WorldBriefing? {
        let interacted = Set(state.interactions.map(\.pulseID))
        let nextPulses = state.activePulses.filter {
            !interacted.contains($0.id) && $0.phase(at: date) != .resolved && $0.expiresAt > date
        }
        guard !nextPulses.isEmpty else { return nil }
        if let last = state.lastBriefingAt, date.timeIntervalSince(last) < 30 * 60 {
            return nil
        }
        let recommended = nextPulses.first
        let summary: String
        if let recommended {
            summary = "The atlas moved while you were away. \(PulsePresentation.title(for: recommended.kind)) is \(PulsePresentation.name(for: recommended.phase(at: date)).lowercased()) nearby."
        } else {
            summary = "The atlas moved while you were away."
        }
        var next = state
        next.lastBriefingAt = date
        replaceState(next)
        return WorldBriefing(
            id: "briefing:\(Int(date.timeIntervalSince1970 / 1800))",
            createdAt: date,
            changedPulseIDs: nextPulses.map(\.id),
            reports: Array(state.reports.suffix(3)),
            summary: summary,
            recommendedPulseID: recommended?.id
        )
    }

    func clear() {
        state = .empty()
        database.savePulseState(state)
    }

    func clearCloudState() {
        clear()
    }

    func resetLocalSession() {
        state = .empty()
    }

    func replaceState(_ next: PulseState) {
        // Callers may intentionally use an injected historical clock in tests or
        // restore a cached Pulse before advancing it against the current clock.
        let sanitized = Self.sanitized(next, now: .distantPast)
        guard sanitized != state else { return }
        state = sanitized
        database.savePulseState(sanitized)
    }

    private static func sanitized(_ state: PulseState, now: Date) -> PulseState {
        var next = state
        next.activePulses = Array(state.activePulses
            .map { $0.refreshed(at: now) }
            .filter { $0.expiresAt > now || $0.resolvedAction != nil }
            .suffix(PulseEngine.maximumActivePulses))
        next.interactions = Array(state.interactions.suffix(100))
        next.reports = Array(state.reports.suffix(20))
        next.claimConditions = state.claimConditions.filter { $0.value.effectiveUntil > now }
        return next
    }
}
