import Foundation
import Combine
import CoreLocation

@MainActor
final class WeatherStore: ObservableObject {
    @Published private(set) var state: WeatherCacheState
    private let database: AtlasDatabase
    private let repository: WeatherRepository

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil, repository: WeatherRepository = WeatherRepository()) {
        if let database { self.database = database }
        else if let fileURL { self.database = AtlasDatabase.makeIsolated(fileURL: fileURL) }
        else { self.database = .shared }
        self.repository = repository
        state = self.database.loadWeatherState() ?? .empty()
        if self.database.loadWeatherState() == nil { self.database.saveWeatherState(state) }
    }

    var snapshots: [String: WeatherSnapshot] { state.snapshots }

    func snapshot(for cellID: String, now: Date = .now) -> WeatherSnapshot? {
        guard let snapshot = state.snapshots[cellID], snapshot.expiresAt > now else { return nil }
        return snapshot
    }

    func replace(_ snapshots: [WeatherSnapshot], at date: Date = .now) {
        var next = state
        for snapshot in snapshots { next.snapshots[snapshot.cellID] = snapshot }
        next.lastRefreshAt = date
        state = next
        database.saveWeatherState(next)
    }

    func refresh(around coordinate: CLLocationCoordinate2D, tileEngine: TileEngine, at date: Date = .now) async {
        let tile = tileEngine.axialCoordinate(for: coordinate)
        let cellID = WeatherCellEngine().cellID(for: tile, tileEngine: tileEngine)
        if let cached = snapshot(for: cellID, now: date), cached.expiresAt.timeIntervalSince(date) > 30 * 60 { return }
        guard let snapshot = await repository.fetch(cellID: cellID, latitude: coordinate.latitude, longitude: coordinate.longitude) else { return }
        replace([snapshot], at: date)
    }

    func replaceCloudState(_ state: WeatherCacheState) {
        self.state = state
        database.saveWeatherState(state)
    }

    func clear() {
        state = .empty()
        database.saveWeatherState(state)
    }

    func resetLocalSession() { state = .empty() }
}
