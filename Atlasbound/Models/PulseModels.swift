import Foundation

/// A temporary world condition. Pulse geometry is always derived from its tile ID.
enum PulseKind: String, Codable, Sendable, CaseIterable, Hashable {
    case signalDrift
    case fogFront
    case resourceBloom
    case surveyEcho
    case landmarkResonance
    case relayInstability

    var title: String {
        switch self {
        case .signalDrift: "Signal drift"
        case .fogFront: "Fog front"
        case .resourceBloom: "Resource bloom"
        case .surveyEcho: "Survey echo"
        case .landmarkResonance: "Landmark resonance"
        case .relayInstability: "Relay instability"
        }
    }

    var detail: String {
        switch self {
        case .signalDrift: "A roaming signal is crossing the nearby atlas."
        case .fogFront: "The local fog is thinning and revealing a temporary pattern."
        case .resourceBloom: "A short-lived vein is brightening beneath the route."
        case .surveyEcho: "Old visits are resolving into a shape worth revisiting."
        case .landmarkResonance: "A nearby landmark is carrying an unusual atlas echo."
        case .relayInstability: "A field relay is asking for attention before the signal fades."
        }
    }

    var symbolName: String {
        switch self {
        case .signalDrift: "dot.radiowaves.left.and.right"
        case .fogFront: "cloud.fog.fill"
        case .resourceBloom: "sparkles"
        case .surveyEcho: "waveform.path.ecg"
        case .landmarkResonance: "mappin.and.ellipse"
        case .relayInstability: "bolt.trianglebadge.exclamationmark.fill"
        }
    }
}

enum PulsePhase: String, Codable, Sendable, CaseIterable, Hashable {
    case detected
    case developing
    case peak
    case resolved

    var displayName: String {
        switch self {
        case .detected: "Detected"
        case .developing: "Developing"
        case .peak: "At peak"
        case .resolved: "Resolved"
        }
    }
}

enum PulseAction: String, Codable, Sendable, CaseIterable, Hashable {
    case observe
    case stabilize
    case harvest

    var title: String {
        switch self {
        case .observe: "Observe"
        case .stabilize: "Stabilize"
        case .harvest: "Harvest"
        }
    }

    var detail: String {
        switch self {
        case .observe: "Record what changed and keep the signal for the atlas."
        case .stabilize: "Use a field tool to leave the area in a better state."
        case .harvest: "Take the immediate materials before the opportunity fades."
        }
    }
}

enum ClaimCondition: String, Codable, Sendable, CaseIterable, Hashable {
    case quiet
    case awake
    case overgrown
    case charged
    case watched
    case unstable

    var title: String {
        switch self {
        case .quiet: "Quiet"
        case .awake: "Awake"
        case .overgrown: "Overgrown"
        case .charged: "Charged"
        case .watched: "Watched"
        case .unstable: "Unstable"
        }
    }

    var symbolName: String {
        switch self {
        case .quiet: "moon.stars.fill"
        case .awake: "sunrise.fill"
        case .overgrown: "leaf.fill"
        case .charged: "bolt.fill"
        case .watched: "eye.fill"
        case .unstable: "exclamationmark.triangle.fill"
        }
    }

    var detail: String {
        switch self {
        case .quiet: "The sector is resting at its normal rhythm."
        case .awake: "Discovery signals are easier to notice here."
        case .overgrown: "Revisits and survey tools find more texture here."
        case .charged: "Factory and relay signals are unusually strong here."
        case .watched: "Scouts are returning sharper reports from this sector."
        case .unstable: "A voluntary field action could shape what happens next."
        }
    }
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
        next.phase = phase(at: date)
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

    var title: String {
        switch self {
        case .chart: "Chart"
        case .listen: "Listen"
        case .tend: "Tend"
        case .salvage: "Salvage"
        }
    }

    var detail: String {
        switch self {
        case .chart: "Favor fog-edge discoveries and route reports."
        case .listen: "Favor early signals and landmark echoes."
        case .tend: "Favor claim conditions and Home Base reports."
        case .salvage: "Favor resource and factory reports."
        }
    }
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
    var claimConditions: [String: ClaimConditionState]
    var scoutStance: ScoutStance
    var reports: [ScoutReport]
    var lastBriefingAt: Date?
    var lastRefreshAt: Date

    static func empty(at date: Date = .now) -> PulseState {
        PulseState(
            activePulses: [],
            interactions: [],
            claimConditions: [:],
            scoutStance: .listen,
            reports: [],
            lastBriefingAt: nil,
            lastRefreshAt: date
        )
    }
}
