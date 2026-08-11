import Foundation
import Combine
import CoreLocation

@MainActor
final class BiomeStore: ObservableObject {
    @Published private(set) var state: BiomeCacheState

    private let database: AtlasDatabase
    private let repository: BiomeRepository
    private var inFlight: [String: Task<BiomeSnapshot?, Never>] = [:]

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil, repository: BiomeRepository = BiomeRepository()) {
        if let database { self.database = database }
        else if let fileURL { self.database = AtlasDatabase.makeIsolated(fileURL: fileURL) }
        else { self.database = .shared }
        self.repository = repository
        state = self.database.loadBiomeState() ?? .empty()
        if self.database.loadBiomeState() == nil { self.database.saveBiomeState(state) }
    }

    var snapshots: [String: BiomeSnapshot] {
        state.snapshots.filter { $0.value.expiresAt > .now }
    }

    func snapshot(for tile: TileCoordinate, tileEngine: TileEngine, now: Date = .now) -> BiomeSnapshot? {
        let id = BiomeCellEngine().cellID(for: tile, tileEngine: tileEngine)
        guard let snapshot = state.snapshots[id], snapshot.expiresAt > now else { return nil }
        return snapshot
    }

    func replace(_ snapshots: [BiomeSnapshot], at date: Date = .now) {
        var next = state
        for snapshot in snapshots { next.snapshots[snapshot.cellID] = snapshot }
        next.lastRefreshAt = date
        state = next
        database.saveBiomeState(next)
    }

    func refresh(around coordinate: CLLocationCoordinate2D, tileEngine: TileEngine, at date: Date = .now) async {
        let tile = tileEngine.axialCoordinate(for: coordinate)
        let cellID = BiomeCellEngine().cellID(for: tile, tileEngine: tileEngine)
        if let cached = snapshot(for: tile, tileEngine: tileEngine, now: date), cached.expiresAt.timeIntervalSince(date) > 60 * 60 { return }
        if let request = inFlight[cellID] {
            _ = await request.value
            return
        }
        let request = Task { await repository.fetch(cellID: cellID, latitude: coordinate.latitude, longitude: coordinate.longitude) }
        inFlight[cellID] = request
        let snapshot = await request.value
        inFlight[cellID] = nil
        if let snapshot { replace([snapshot], at: date) }
    }

    func clear() {
        state = .empty()
        database.saveBiomeState(state)
    }

    func resetLocalSession() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        state = .empty()
    }
}
