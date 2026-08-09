import Foundation
import CoreLocation

/// Pure helpers for coarse-cell place labels returned by Mapbox Geocoding.
struct RegionLookupEngine: Sendable {
    /// ~0.02° ≈ 2 km cells so neighboring hex tiles share one reverse-geocode.
    static let cellDegrees: Double = 0.02

    struct PlaceLabels: Sendable, Hashable, Codable {
        var countryCode: String?
        var countryName: String?
        var administrativeArea: String?
        var locality: String?

        var isEmpty: Bool {
            countryDisplayName == nil && administrativeArea == nil && locality == nil
        }

        var countryDisplayName: String? {
            let name = countryName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty { return name }
            let code = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let code, !code.isEmpty { return code }
            return nil
        }

        /// Stable country key preferring ISO code when present.
        var countryKey: String? {
            let code = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let code, !code.isEmpty { return "iso:\(code)" }
            if let name = countryDisplayName { return "name:\(name)" }
            return nil
        }

        var provinceKey: String? {
            guard let admin = administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !admin.isEmpty else { return nil }
            let country = countryKey ?? "unknown"
            return "\(country)|admin:\(admin)"
        }

        var cityKey: String? {
            guard let city = locality?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !city.isEmpty else { return nil }
            let province = provinceKey ?? countryKey ?? "unknown"
            return "\(province)|locality:\(city)"
        }
    }

    struct PlaceEntry: Sendable, Hashable {
        let key: String
        let name: String
        let tileCount: Int
    }

    struct PlacesVisitedSummary: Sendable {
        let countries: [PlaceEntry]
        let provinces: [PlaceEntry]
        let cities: [PlaceEntry]

        var isEmpty: Bool {
            countries.isEmpty && provinces.isEmpty && cities.isEmpty
        }
    }

    /// Quantize a coordinate into a stable cache cell key.
    static func cellKey(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = quantize(coordinate.latitude)
        let lon = quantize(coordinate.longitude)
        return String(format: "%.2f:%.2f", lat, lon)
    }

    static func representativeCoordinate(forCellKey key: String) -> CLLocationCoordinate2D? {
        let parts = key.split(separator: ":")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    static func labels(
        countryCode: String?,
        countryName: String?,
        administrativeArea: String?,
        locality: String?
    ) -> PlaceLabels {
        PlaceLabels(
            countryCode: cleaned(countryCode),
            countryName: cleaned(countryName),
            administrativeArea: cleaned(administrativeArea),
            locality: cleaned(locality)
        )
    }

    static func labels(fromMapboxFeatures features: [[String: Any]]) -> PlaceLabels {
        var countryCode: String?
        var countryName: String?
        var administrativeArea: String?
        var locality: String?
        for feature in features {
            let properties = feature["properties"] as? [String: Any] ?? [:]
            var candidates: [[String: Any]] = [feature]
            if let context = properties["context"] as? [String: Any] {
                for (kind, value) in context {
                    guard var item = value as? [String: Any] else { continue }
                    if item["feature_type"] == nil { item["feature_type"] = kind }
                    candidates.append(item)
                }
            }
            for candidate in candidates {
                let candidateProperties = candidate["properties"] as? [String: Any] ?? candidate
                let featureType = candidateProperties["feature_type"] as? String
                let id = (featureType ?? candidate["id"] as? String ?? "").lowercased()
                let text = candidateProperties["name"] as? String
                    ?? candidateProperties["name_preferred"] as? String
                    ?? candidateProperties["text"] as? String
                    ?? candidate["text"] as? String
                let parsedCountryCode = candidateProperties["country_code"] as? String
                let shortCode = candidateProperties["short_code"] as? String
                if id.hasPrefix("country") {
                    countryName = text ?? countryName
                    countryCode = parsedCountryCode ?? shortCode ?? countryCode
                } else if id.hasPrefix("region") || id.hasPrefix("district") {
                    administrativeArea = text ?? administrativeArea
                } else if id.hasPrefix("place") || id.hasPrefix("locality") || id.hasPrefix("city") {
                    locality = text ?? locality
                }
            }
        }
        return labels(countryCode: countryCode, countryName: countryName, administrativeArea: administrativeArea, locality: locality)
    }

    /// Build places-visited aggregates from cell labels weighted by tile counts.
    static func placesVisited(
        cellLabels: [String: PlaceLabels],
        tileCountsByCell: [String: Int]
    ) -> PlacesVisitedSummary {
        var countryTotals: [String: (name: String, count: Int)] = [:]
        var provinceTotals: [String: (name: String, count: Int)] = [:]
        var cityTotals: [String: (name: String, count: Int)] = [:]

        for (cell, labels) in cellLabels {
            let tiles = max(0, tileCountsByCell[cell, default: 0])
            guard tiles > 0 else { continue }

            if let key = labels.countryKey, let name = labels.countryDisplayName {
                let existing = countryTotals[key]
                countryTotals[key] = (name, (existing?.count ?? 0) + tiles)
            }
            if let key = labels.provinceKey,
               let name = cleaned(labels.administrativeArea) {
                let existing = provinceTotals[key]
                provinceTotals[key] = (name, (existing?.count ?? 0) + tiles)
            }
            if let key = labels.cityKey,
               let name = cleaned(labels.locality) {
                let existing = cityTotals[key]
                cityTotals[key] = (name, (existing?.count ?? 0) + tiles)
            }
        }

        return PlacesVisitedSummary(
            countries: sortedEntries(countryTotals),
            provinces: sortedEntries(provinceTotals),
            cities: sortedEntries(cityTotals)
        )
    }

    /// Count canonical atlas tiles per coarse place-label cell.
    static func tileCountsByCell(tiles: [WorldTile]) -> [String: Int] {
        var counts: [String: Int] = [:]
        let engine = TileEngine(option: .twenty)
        for tile in tiles where tile.isDiscovered {
            let center = engine.centerCoordinate(for: tile.coordinate)
            let key = cellKey(for: center)
            counts[key, default: 0] += 1
        }
        return counts
    }

    // MARK: - Private

    private static func quantize(_ value: Double) -> Double {
        (value / cellDegrees).rounded() * cellDegrees
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func sortedEntries(
        _ totals: [String: (name: String, count: Int)]
    ) -> [PlaceEntry] {
        totals
            .map { PlaceEntry(key: $0.key, name: $0.value.name, tileCount: $0.value.count) }
            .sorted {
                if $0.tileCount != $1.tileCount { return $0.tileCount > $1.tileCount }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
