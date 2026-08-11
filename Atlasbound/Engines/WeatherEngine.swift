import Foundation

struct WeatherCellEngine: Sendable {
    /// Weather cells are 8 coarse sectors wide (roughly 5–6 km at the 20 m grid).
    static let sectorStride = 8

    func cellID(for tile: TileCoordinate, tileEngine: TileEngine) -> String {
        let sector = HexSectorEngine().sectorCoordinate(for: tile)
        let q = floorDiv(sector.q, Self.sectorStride)
        let r = floorDiv(sector.r, Self.sectorStride)
        return "weather:\(Int(tileEngine.tileSizeMeters.rounded())):\(q):\(r)"
    }

    private func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder >= 0 ? quotient : quotient - 1
    }
}

struct WeatherEngine: Sendable {
    func condition(temperatureC: Double, precipitationMM: Double, windKPH: Double, weatherCode: Int? = nil) -> WeatherCondition {
        if let weatherCode, [95, 96, 99].contains(weatherCode) { return .storm }
        if let weatherCode, [45, 48].contains(weatherCode) { return .fog }
        if let weatherCode, [71, 73, 75, 77, 85, 86].contains(weatherCode) { return .snow }
        if let weatherCode, [2, 3].contains(weatherCode) { return .cloudy }
        if temperatureC <= 0 && precipitationMM > 0 { return .frost }
        if temperatureC >= 32 { return .heat }
        if windKPH >= 35 { return .wind }
        if precipitationMM >= 8 { return .storm }
        if precipitationMM > 0.2 { return .rain }
        return .clear
    }

    func modifiers(for snapshot: WeatherSnapshot?) -> WeatherModifiers {
        guard let snapshot else { return .neutral }
        let modifiers: WeatherModifiers
        switch snapshot.condition {
        case .clear:
            modifiers = WeatherModifiers(cropYield: 1, extractionYield: 1, solarPower: 1.2, windPower: 0.8, roadThroughput: 1)
        case .cloudy:
            modifiers = WeatherModifiers(cropYield: 1, extractionYield: 1, solarPower: 0.85, windPower: 1, roadThroughput: 1)
        case .rain:
            modifiers = WeatherModifiers(cropYield: 1.2, extractionYield: 1, solarPower: 0.7, windPower: 1, roadThroughput: 0.9)
        case .storm:
            modifiers = WeatherModifiers(cropYield: 1.05, extractionYield: 0.85, solarPower: 0.45, windPower: 1.35, roadThroughput: 0.65)
        case .frost:
            modifiers = WeatherModifiers(cropYield: 0.55, extractionYield: 0.95, solarPower: 0.8, windPower: 0.95, roadThroughput: 0.9)
        case .snow:
            modifiers = WeatherModifiers(cropYield: 0.7, extractionYield: 0.9, solarPower: 0.75, windPower: 1, roadThroughput: 0.8)
        case .fog:
            modifiers = WeatherModifiers(cropYield: 1, extractionYield: 1, solarPower: 0.82, windPower: 1, roadThroughput: 0.92)
        case .heat:
            modifiers = WeatherModifiers(cropYield: 0.7, extractionYield: 1, solarPower: 1.15, windPower: 0.9, roadThroughput: 1)
        case .wind:
            modifiers = WeatherModifiers(cropYield: 0.9, extractionYield: 1, solarPower: 0.9, windPower: 1.25, roadThroughput: 0.85)
        }
        func cap(_ value: Double) -> Double { min(1.35, max(0.80, value)) }
        return WeatherModifiers(
            cropYield: cap(modifiers.cropYield), extractionYield: cap(modifiers.extractionYield),
            solarPower: cap(modifiers.solarPower), windPower: cap(modifiers.windPower),
            roadThroughput: cap(modifiers.roadThroughput)
        )
    }
}

struct WeatherModifiers: Equatable, Sendable {
    let cropYield: Double
    let extractionYield: Double
    let solarPower: Double
    let windPower: Double
    let roadThroughput: Double

    static let neutral = WeatherModifiers(cropYield: 1, extractionYield: 1, solarPower: 1, windPower: 1, roadThroughput: 1)
}
