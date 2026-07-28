import Foundation
import Combine
import CoreLocation

/// Caches reverse-geocoded place labels for coarse map cells (no hex geometry).
@MainActor
final class RegionLookupStore: ObservableObject {
    @Published private(set) var cells: [String: PersistedRegionCell] = [:]
    @Published private(set) var isResolving = false
    @Published private(set) var resolvedCellCount = 0

    private let fileURL: URL
    private var resolveTask: Task<Void, Never>?
    private let failureBackoff: TimeInterval = 6 * 60 * 60

    private static let fileName = "atlasbound-regions.json"

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? JSONFileStore.documentsURL(fileName: Self.fileName)
        loadFromDisk()
        resolvedCellCount = cells.values.filter(\.didSucceed).count
    }

    /// Labels for successfully resolved cells only.
    var successfulLabels: [String: RegionLookupEngine.PlaceLabels] {
        var result: [String: RegionLookupEngine.PlaceLabels] = [:]
        for (key, cell) in cells where cell.didSucceed {
            result[key] = cell.labels
        }
        return result
    }

    func placesVisited(tilesBySize: [Int: [WorldTile]]) -> RegionLookupEngine.PlacesVisitedSummary {
        let counts = RegionLookupEngine.tileCountsByCell(tilesBySize: tilesBySize)
        return RegionLookupEngine.placesVisited(
            cellLabels: successfulLabels,
            tileCountsByCell: counts
        )
    }

    /// Resolve uncached / retryable cells for discovered tiles. Safe to call repeatedly.
    func resolve(tilesBySize: [Int: [WorldTile]]) {
        let counts = RegionLookupEngine.tileCountsByCell(tilesBySize: tilesBySize)
        let pendingKeys = counts.keys.filter { needsResolve(cellKey: $0) }.sorted()
        guard !pendingKeys.isEmpty else { return }

        resolveTask?.cancel()
        resolveTask = Task { [weak self] in
            await self?.resolveCells(pendingKeys)
        }
    }

    // MARK: - Resolve

    private func needsResolve(cellKey: String) -> Bool {
        guard let existing = cells[cellKey] else { return true }
        if existing.didSucceed { return false }
        guard let failedAt = existing.failedAt else { return true }
        return Date().timeIntervalSince(failedAt) >= failureBackoff
    }

    private func resolveCells(_ keys: [String]) async {
        isResolving = true
        defer { isResolving = false }

        var dirty = false
        for key in keys {
            if Task.isCancelled { break }
            guard let coordinate = RegionLookupEngine.representativeCoordinate(forCellKey: key) else {
                continue
            }

            let placemark = await GeocodeLimiter.shared.reverseGeocode(at: coordinate)
            if Task.isCancelled { break }

            if let placemark {
                let labels = RegionLookupEngine.labels(from: placemark)
                if labels.isEmpty {
                    cells[key] = PersistedRegionCell.failed(cellKey: key, at: Date())
                } else {
                    cells[key] = PersistedRegionCell(cellKey: key, labels: labels, resolvedAt: Date())
                }
            } else {
                cells[key] = PersistedRegionCell.failed(cellKey: key, at: Date())
            }
            dirty = true
            resolvedCellCount = cells.values.filter(\.didSucceed).count
        }

        if dirty {
            persistToDisk()
        }
    }

    // MARK: - Disk

    private struct SaveFile: Codable {
        var version: Int?
        var cells: [PersistedRegionCell]
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let save = JSONFileStore.load(SaveFile.self, from: fileURL) else {
            cells = [:]
            return
        }
        cells = Dictionary(uniqueKeysWithValues: save.cells.map { ($0.cellKey, $0) })
    }

    private func persistToDisk() {
        let save = SaveFile(
            version: JSONFileStore.currentSchemaVersion,
            cells: cells.values.sorted { $0.cellKey < $1.cellKey }
        )
        JSONFileStore.save(save, to: fileURL)
    }
}

/// One reverse-geocode cache entry keyed by coarse lat/lon cell (no geometry).
struct PersistedRegionCell: Codable, Hashable, Sendable {
    var cellKey: String
    var countryCode: String?
    var countryName: String?
    var administrativeArea: String?
    var locality: String?
    var resolvedAt: Date?
    var failedAt: Date?

    var didSucceed: Bool { failedAt == nil && resolvedAt != nil }

    var labels: RegionLookupEngine.PlaceLabels {
        RegionLookupEngine.labels(
            countryCode: countryCode,
            countryName: countryName,
            administrativeArea: administrativeArea,
            locality: locality
        )
    }

    init(cellKey: String, labels: RegionLookupEngine.PlaceLabels, resolvedAt: Date) {
        self.cellKey = cellKey
        self.countryCode = labels.countryCode
        self.countryName = labels.countryName
        self.administrativeArea = labels.administrativeArea
        self.locality = labels.locality
        self.resolvedAt = resolvedAt
        self.failedAt = nil
    }

    static func failed(cellKey: String, at date: Date) -> PersistedRegionCell {
        PersistedRegionCell(
            cellKey: cellKey,
            countryCode: nil,
            countryName: nil,
            administrativeArea: nil,
            locality: nil,
            resolvedAt: nil,
            failedAt: date
        )
    }

    private init(
        cellKey: String,
        countryCode: String?,
        countryName: String?,
        administrativeArea: String?,
        locality: String?,
        resolvedAt: Date?,
        failedAt: Date?
    ) {
        self.cellKey = cellKey
        self.countryCode = countryCode
        self.countryName = countryName
        self.administrativeArea = administrativeArea
        self.locality = locality
        self.resolvedAt = resolvedAt
        self.failedAt = failedAt
    }
}
