import Foundation

/// Display copy and symbols for Pulse domain cases. These values are not persisted.
enum PulsePresentation {
    static func title(for kind: PulseKind) -> String {
        switch kind {
        case .signalDrift: "Signal drift"
        case .fogFront: "Fog front"
        case .resourceBloom: "Resource bloom"
        case .surveyEcho: "Survey echo"
        case .landmarkResonance: "Landmark resonance"
        case .relayInstability: "Relay instability"
        }
    }

    static func detail(for kind: PulseKind) -> String {
        switch kind {
        case .signalDrift: "A roaming signal is crossing the nearby atlas."
        case .fogFront: "The local fog is thinning and revealing a temporary pattern."
        case .resourceBloom: "A short-lived vein is brightening beneath the route."
        case .surveyEcho: "Old visits are resolving into a shape worth revisiting."
        case .landmarkResonance: "A nearby landmark is carrying an unusual atlas echo."
        case .relayInstability: "A field relay is asking for attention before the signal fades."
        }
    }

    static func symbolName(for kind: PulseKind) -> String {
        switch kind {
        case .signalDrift: "dot.radiowaves.left.and.right"
        case .fogFront: "cloud.fog.fill"
        case .resourceBloom: "sparkles"
        case .surveyEcho: "waveform.path.ecg"
        case .landmarkResonance: "mappin.and.ellipse"
        case .relayInstability: "bolt.trianglebadge.exclamationmark.fill"
        }
    }

    static func name(for phase: PulsePhase) -> String {
        switch phase {
        case .detected: "Detected"
        case .developing: "Developing"
        case .peak: "At peak"
        case .resolved: "Resolved"
        }
    }

    static func title(for action: PulseAction) -> String {
        switch action {
        case .observe: "Observe"
        case .stabilize: "Stabilize"
        case .harvest: "Harvest"
        }
    }

    static func detail(for action: PulseAction) -> String {
        switch action {
        case .observe: "Record what changed and keep the signal for the atlas."
        case .stabilize: "Use a field tool to leave the area in a better state."
        case .harvest: "Take the immediate materials before the opportunity fades."
        }
    }

    static func title(for stance: ScoutStance) -> String {
        switch stance {
        case .chart: "Chart"
        case .listen: "Listen"
        case .tend: "Tend"
        case .salvage: "Salvage"
        }
    }

    static func detail(for stance: ScoutStance) -> String {
        switch stance {
        case .chart: "Favor fog-edge discoveries and route reports."
        case .listen: "Favor early signals and landmark echoes."
        case .tend: "Favor claim conditions and Home Base reports."
        case .salvage: "Favor resource and factory reports."
        }
    }
}
