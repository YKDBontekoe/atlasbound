import Foundation
import Combine
import CoreLocation

/// Caches reverse-geocoded place labels for coarse map cells (no hex geometry).
@MainActor
final class RegionLookupStore: ObservableObject {
    @Published private(set) var cells: [String: PersistedRegionCell] = [:]
    @Published private(set) var isResolving = false
    @Published private(set) var resolvedCellCount = 0

    private let database: AtlasDatabase
    private var resolveTask: Task<Void, Never>?
    private var pendingCellKeys: Set<String> = []
    private let failureBackoff: TimeInterval = 6 * 60 * 60

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL))
        } else {
            self.database = .shared
        }
        loadFromDisk()
        resolvedCellCount = cells.values.filter(\.didSucceed).count
    }

    private static func sqliteURL(from fileURL: URL) -> URL {
        fileURL.pathExtension.lowercased() == "json"
            ? fileURL.deletingPathExtension().appendingPathExtension("sqlite")
            : fileURL
    }

    /// Labels for successfully resolved cells only.
    var successfulLabels: [String: RegionLookupEngine.PlaceLabels] {
        var result: [String: RegionLookupEngine.PlaceLabels] = [:]
        for (key, cell) in cells where cell.didSucceed {
            result[key] = cell.labels
        }
        return result
    }

    func placesVisited(tiles: [WorldTile]) -> RegionLookupEngine.PlacesVisitedSummary {
        let counts = RegionLookupEngine.tileCountsByCell(tiles: tiles)
        return RegionLookupEngine.placesVisited(
            cellLabels: successfulLabels,
            tileCountsByCell: counts
        )
    }

    /// Resolve uncached / retryable cells for discovered tiles. Safe to call repeatedly.
    func resolve(tiles: [WorldTile]) {
        let counts = RegionLookupEngine.tileCountsByCell(tiles: tiles)
        pendingCellKeys.formUnion(counts.keys.filter { needsResolve(cellKey: $0) })
        guard !pendingCellKeys.isEmpty, resolveTask == nil else { return }

        resolveTask = Task { [weak self] in
            await self?.drainResolveQueue()
        }
    }

    // MARK: - Resolve

    private func needsResolve(cellKey: String) -> Bool {
        guard let existing = cells[cellKey] else { return true }
        if existing.didSucceed { return false }
        guard let failedAt = existing.failedAt else { return true }
        return Date().timeIntervalSince(failedAt) >= failureBackoff
    }

    private func drainResolveQueue() async {
        isResolving = true
        defer {
            isResolving = false
            resolveTask = nil
        }

        var dirty = false
        while !pendingCellKeys.isEmpty {
            let keys = pendingCellKeys.sorted()
            pendingCellKeys.removeAll()
            for key in keys {
                if Task.isCancelled { break }
                guard needsResolve(cellKey: key),
                      let coordinate = RegionLookupEngine.representativeCoordinate(forCellKey: key) else {
                    continue
                }

                let placemark = await GeocodeLimiter.shared.reverseGeocode(at: coordinate)
                if Task.isCancelled { break }

                if let placemark {
                    let labels = RegionLookupEngine.labels(from: placemark)
                    if labels.isEmpty {
                        setCell(.failed(cellKey: key, at: Date()), forKey: key)
                    } else {
                        setCell(PersistedRegionCell(cellKey: key, labels: labels, resolvedAt: Date()), forKey: key)
                    }
                } else {
                    setCell(.failed(cellKey: key, at: Date()), forKey: key)
                }
                dirty = true
            }
            if Task.isCancelled { break }
        }

        if dirty {
            persistToDisk()
        }
    }

    private func setCell(_ cell: PersistedRegionCell, forKey key: String) {
        let wasSuccessful = cells[key]?.didSucceed == true
        cells[key] = cell
        if wasSuccessful != cell.didSucceed {
            resolvedCellCount += cell.didSucceed ? 1 : -1
        }
    }

    // MARK: - Disk

    private func loadFromDisk() {
        cells = database.loadRegionCells().filter { key, _ in
            RegionLookupEngine.representativeCoordinate(forCellKey: key) != nil
        }
    }

    private func persistToDisk() {
        for cell in cells.values {
            database.upsertRegionCell(cell)
        }
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

    init(
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
