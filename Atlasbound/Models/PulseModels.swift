import Foundation

/// A temporary world condition. Pulse geometry is always derived from its tile ID.
enum PulseKind: String, Codable, Sendable, CaseIterable, Hashable {
    case signalDrift
    case fogFront
    case resourceBloom
    case surveyEcho
    case landmarkResonance
    case relayInstability

}

enum PulsePhase: String, Codable, Sendable, CaseIterable, Hashable {
    case detected
    case developing
    case peak
    case resolved

}

enum PulseAction: String, Codable, Sendable, CaseIterable, Hashable {
    case observe
    case stabilize
    case harvest

}

enum ClaimCondition: String, Codable, Sendable, CaseIterable, Hashable {
    case quiet
    case awake
    case overgrown
    case charged
    case watched
    case unstable

}

struct ClaimConditionState: Codable, Hashable, Sendable {
    var condition: ClaimCondition
    var effectiveFrom: Date
    var effectiveUntil: Date
    var sourcePulseID: String?

    var isActive: Bool { effectiveUntil > .now }
}

struct AtlasPulse: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: PulseKind
    let anchorTileID: String
    let startedAt: Date
    let phaseEndsAt: [PulsePhase: Date]
    let expiresAt: Date
    let seed: UInt64
    var phase: PulsePhase
    var resolvedAction: PulseAction?

    var isActive: Bool { phase != .resolved && expiresAt > .now }

    func phase(at date: Date) -> PulsePhase {
        guard date < expiresAt else { return .resolved }
        if let peak = phaseEndsAt[.peak], date >= peak { return .peak }
        if let developing = phaseEndsAt[.developing], date >= developing { return .developing }
        return .detected
    }

    func refreshed(at date: Date) -> AtlasPulse {
        var next = self
        next.phase = resolvedAction == nil ? phase(at: date) : .resolved
        return next
    }
}

struct PulseInteraction: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let pulseID: String
    let action: PulseAction
    let createdAt: Date
    let outcome: PulseOutcome
}

struct PulseRewardGrant: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let pulseID: String
    let itemID: String
    let quantity: Int
    let createdAt: Date
}

enum PulseActionResult: Sendable, Equatable {
    case completed(PulseInteraction)
    case denied(String)
}

struct PulseOutcome: Codable, Hashable, Sendable {
    let title: String
    let detail: String
    let rewardItemID: String?
    let rewardQuantity: Int
    let claimCondition: ClaimCondition?
}

enum ScoutStance: String, Codable, Sendable, CaseIterable, Hashable {
    case chart
    case listen
    case tend
    case salvage

}

struct ScoutReport: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let createdAt: Date
    let stance: ScoutStance
    let title: String
    let detail: String
    let pulseID: String?
    let sectorID: String?
}

struct WorldBriefing: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let createdAt: Date
    let changedPulseIDs: [String]
    let reports: [ScoutReport]
    let summary: String
    let recommendedPulseID: String?
}

struct PulseState: Codable, Hashable, Sendable {
    static let schemaVersion = 1

    var activePulses: [AtlasPulse]
    var interactions: [PulseInteraction]
    var pendingRewardGrants: [PulseRewardGrant]
    var claimConditions: [String: ClaimConditionState]
    var scoutStance: ScoutStance
    var reports: [ScoutReport]
    var lastBriefingAt: Date?
    var lastRefreshAt: Date

    static func empty(at date: Date = .now) -> PulseState {
        PulseState(
            activePulses: [],
            interactions: [],
            pendingRewardGrants: [],
            claimConditions: [:],
            scoutStance: .listen,
            reports: [],
            lastBriefingAt: nil,
            lastRefreshAt: date
        )
    }

    private enum CodingKeys: String, CodingKey {
        case activePulses, interactions, pendingRewardGrants, claimConditions
        case scoutStance, reports, lastBriefingAt, lastRefreshAt
    }

    init(
        activePulses: [AtlasPulse],
        interactions: [PulseInteraction],
        pendingRewardGrants: [PulseRewardGrant] = [],
        claimConditions: [String: ClaimConditionState],
        scoutStance: ScoutStance,
        reports: [ScoutReport],
        lastBriefingAt: Date?,
        lastRefreshAt: Date
    ) {
        self.activePulses = activePulses
        self.interactions = interactions
        self.pendingRewardGrants = pendingRewardGrants
        self.claimConditions = claimConditions
        self.scoutStance = scoutStance
        self.reports = reports
        self.lastBriefingAt = lastBriefingAt
        self.lastRefreshAt = lastRefreshAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activePulses = try container.decode([AtlasPulse].self, forKey: .activePulses)
        interactions = try container.decode([PulseInteraction].self, forKey: .interactions)
        pendingRewardGrants = try container.decodeIfPresent([PulseRewardGrant].self, forKey: .pendingRewardGrants) ?? []
        claimConditions = try container.decode([String: ClaimConditionState].self, forKey: .claimConditions)
        scoutStance = try container.decode(ScoutStance.self, forKey: .scoutStance)
        reports = try container.decode([ScoutReport].self, forKey: .reports)
        lastBriefingAt = try container.decodeIfPresent(Date.self, forKey: .lastBriefingAt)
        lastRefreshAt = try container.decode(Date.self, forKey: .lastRefreshAt)
    }
}
