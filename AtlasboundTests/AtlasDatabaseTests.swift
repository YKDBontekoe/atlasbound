import XCTest
import SQLite3
@testable import Atlasbound

@MainActor
final class AtlasDatabaseTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-db-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempURL.path + "-shm"))
        tempURL = nil
        super.tearDown()
    }

    func testLegacyJSONWorldImport() throws {
        let docs = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }

        let tile = WorldTile(
            id: "hex:20:2:2",
            coordinate: TileCoordinate(q: 2, r: 2),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let world = WorldSaveFile(
            tiles: [PersistedTileRecord(from: tile)],
            progress: PersistedProgressRecord(
                discoveryXPTotal: 100,
                familiarityXPTotal: 25,
                activitiesCompleted: 1
            ),
            frontier: PersistedFrontierRecord(from: .empty)
        )
        JSONFileStore.save(world, to: docs.appendingPathComponent("atlasbound-world.json"))

        let dbURL = docs.appendingPathComponent("atlasbound.sqlite")
        let database = AtlasDatabase(fileURL: dbURL, importLegacyJSON: true)
        let loaded = database.loadWorld()
        XCTAssertEqual(loaded.tiles.count, 1)
        XCTAssertEqual(loaded.tiles["hex:20:2:2"]?.masteryXP, 100)
        XCTAssertEqual(loaded.progress.discoveryXPTotal, 100)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: docs.appendingPathComponent("atlasbound-world.json").path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: docs.appendingPathComponent("atlasbound-world.json.bak").path)
        )
    }

    func testTileColumnsExcludeGeometry() {
        let database = AtlasDatabase.makeIsolated(fileURL: tempURL)
        database.upsertTiles([
            WorldTile(
                id: "hex:20:0:0",
                coordinate: TileCoordinate(q: 0, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        ])
        let loaded = database.loadWorld().tiles["hex:20:0:0"]
        XCTAssertEqual(loaded?.coordinate, TileCoordinate(q: 0, r: 0))
        // Geometry remains derived — PersistedTileRecord still has no polygon fields.
        let keys = Set(Mirror(reflecting: PersistedTileRecord(from: loaded!)).children.compactMap(\.label))
        XCTAssertFalse(keys.contains("polygon"))
        XCTAssertFalse(keys.contains("latitude"))
    }

    func testVersionFiveDatabaseRunsPulseAndWeatherMigrationsAndClearsWeather() throws {
        do {
            let bootstrap = try SQLiteDatabase(fileURL: tempURL)
            try bootstrap.execute("CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);")
            try bootstrap.execute("INSERT INTO meta(key, value) VALUES ('schema_version', '5');")
        }

        let database = AtlasDatabase(fileURL: tempURL, importLegacyJSON: false)
        let snapshot = WeatherSnapshot(
            cellID: "weather:20:0:0",
            condition: .clear,
            temperatureC: 20,
            precipitationMM: 0,
            windKPH: 4,
            cloudCover: 0,
            observedAt: .now,
            expiresAt: .now.addingTimeInterval(3600)
        )
        database.saveWeatherState(WeatherCacheState(snapshots: [snapshot.cellID: snapshot], lastRefreshAt: .now))
        XCTAssertNotNil(database.loadWeatherState())
        database.clearAllLocalState()
        XCTAssertNil(database.loadWeatherState())

        let verifier = try SQLiteDatabase(fileURL: tempURL)
        XCTAssertEqual(try scalar(verifier, "SELECT value FROM meta WHERE key = 'schema_version';"), "7")
        XCTAssertEqual(try scalar(verifier, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'pulse_state';"), "pulse_state")
        XCTAssertEqual(try scalar(verifier, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'weather_state';"), "weather_state")
    }

    private func scalar(_ database: SQLiteDatabase, _ sql: String) throws -> String? {
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return SQLiteDatabase.columnText(statement, index: 0)
    }
}
