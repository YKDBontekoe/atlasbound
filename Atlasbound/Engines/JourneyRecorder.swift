import Foundation

/// Session-scoped recorder for privacy-preserving journey replays.
@MainActor
final class JourneyRecorder {
    private(set) var waypoints: [JourneyWaypoint] = []
    private(set) var moments: [JourneyMoment] = []
    private var startedAt: Date?
    private var lastBiomeCellID: String?
    private var lastWeatherCondition: WeatherCondition?

    func begin(at date: Date) {
        waypoints = []
        moments = []
        startedAt = date
        lastBiomeCellID = nil
        lastWeatherCondition = nil
    }

    func record(tileID: String, at date: Date) {
        guard let startedAt else { return }
        waypoints.append(JourneyWaypoint(tileID: tileID, elapsedSeconds: max(0, Int(date.timeIntervalSince(startedAt).rounded()))))
    }

    func recordEnvironment(tileID: String, biome: BiomeSnapshot?, weather: WeatherSnapshot?, at date: Date) {
        guard let startedAt else { return }
        let elapsed = max(0, Int(date.timeIntervalSince(startedAt).rounded()))
        if let biome, biome.cellID != lastBiomeCellID {
            lastBiomeCellID = biome.cellID
            moments.append(JourneyMoment(
                id: "journey-biome:\(biome.cellID):\(elapsed)", kind: .biomeChanged, tileID: tileID,
                elapsedSeconds: elapsed, title: biome.primary.displayName, detail: biome.traits.map(\.rawValue).sorted().joined(separator: ", ")
            ))
        }
        if let weather, weather.condition != lastWeatherCondition {
            lastWeatherCondition = weather.condition
            moments.append(JourneyMoment(
                id: "journey-weather:\(weather.cellID):\(elapsed)", kind: .weatherChanged, tileID: tileID,
                elapsedSeconds: elapsed, title: weather.condition.displayName, detail: "\(Int(weather.temperatureC.rounded()))°C"
            ))
        }
    }

    func record(kind: JourneyMomentKind, tileID: String, title: String, detail: String, at date: Date) {
        guard let startedAt else { return }
        let elapsed = max(0, Int(date.timeIntervalSince(startedAt).rounded()))
        moments.append(JourneyMoment(
            id: "journey-\(kind.rawValue):\(tileID):\(elapsed):\(moments.count)", kind: kind,
            tileID: tileID, elapsedSeconds: elapsed, title: title, detail: detail
        ))
    }

    func finish() -> JourneyTrack? {
        defer { startedAt = nil }
        let compacted = JourneyEngine().compact(waypoints)
        guard !compacted.isEmpty else { return nil }
        return JourneyTrack(waypoints: compacted, moments: moments.sorted { $0.elapsedSeconds < $1.elapsedSeconds })
    }
}
