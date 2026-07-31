import Foundation
import SQLite3
import os

/// Single-file SQLite persistence for Atlasbound.
/// Geometry is never stored — tiles keep IDs + mastery fields only.
@MainActor
final class AtlasDatabase {
    static let schemaVersion = 1
    static let fileName = "atlasbound.sqlite"

    private static let logger = Logger(subsystem: "com.atlasbound.app", category: "database")
    private static var sharedInstance: AtlasDatabase?

    /// Shared Documents database (imports legacy JSON once).
    static var shared: AtlasDatabase {
        if let sharedInstance { return sharedInstance }
        let url = JSONFileStore.documentsURL(fileName: fileName)
        let database = AtlasDatabase(fileURL: url, importLegacyJSON: true)
        sharedInstance = database
        return database
    }

    /// Reset the shared handle — tests only.
    static func resetSharedForTests() {
        sharedInstance = nil
    }

    let fileURL: URL
    private let db: SQLiteDatabase
    private let encoder = JSONFileStore.encoder
    private let decoder = JSONFileStore.decoder

    init(fileURL: URL, importLegacyJSON: Bool) {
        self.fileURL = fileURL
        let opened: SQLiteDatabase
        do {
            opened = try SQLiteDatabase(fileURL: fileURL)
        } catch {
            Self.logger.error("Database open failed: \(String(describing: error), privacy: .public)")
            // Fall back to a throwaway file so the app can still run.
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("atlasbound-fallback-\(UUID().uuidString).sqlite")
            // swiftlint:disable:next force_try
            opened = try! SQLiteDatabase(fileURL: fallback)
        }
        db = opened
        try? migrateSchemaIfNeeded()
        if importLegacyJSON {
            importLegacyJSONIfNeeded()
        }
    }

    /// Isolated database for unit tests (no Documents JSON import).
    static func makeIsolated(fileURL: URL) -> AtlasDatabase {
        AtlasDatabase(fileURL: fileURL, importLegacyJSON: false)
    }

    // MARK: - Schema

    private func migrateSchemaIfNeeded() throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS meta (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            );
            """
        )
        let current = Int(metaValue(for: "schema_version") ?? "0") ?? 0
        if current < 1 {
            try db.execute(
                """
                CREATE TABLE IF NOT EXISTS tiles (
                  id TEXT PRIMARY KEY NOT NULL,
                  q INTEGER NOT NULL,
                  r INTEGER NOT NULL,
                  state INTEGER NOT NULL,
                  mastery_xp INTEGER NOT NULL,
                  visit_count INTEGER NOT NULL,
                  unique_visit_days INTEGER NOT NULL,
                  activity_stamps TEXT NOT NULL,
                  first_visited_at REAL,
                  last_visited_at REAL,
                  weekly_charge INTEGER NOT NULL,
                  region_ids TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS progress (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  discovery_xp INTEGER NOT NULL,
                  familiarity_xp INTEGER NOT NULL,
                  activities_completed INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS frontier (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS activity_sessions (
                  id TEXT PRIMARY KEY NOT NULL,
                  payload TEXT NOT NULL,
                  started_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS activity_aggregates (
                  activity TEXT PRIMARY KEY NOT NULL,
                  longest_distance REAL NOT NULL,
                  total_distance REAL NOT NULL,
                  total_duration REAL NOT NULL,
                  session_count INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS region_cells (
                  cell_key TEXT PRIMARY KEY NOT NULL,
                  country_code TEXT,
                  country_name TEXT,
                  administrative_area TEXT,
                  locality TEXT,
                  resolved_at REAL,
                  failed_at REAL
                );

                CREATE TABLE IF NOT EXISTS pinpoint_games (
                  id TEXT PRIMARY KEY NOT NULL,
                  payload TEXT NOT NULL,
                  ended_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS pinpoint_stats (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  high_score_worldwide INTEGER NOT NULL,
                  high_score_home_turf INTEGER NOT NULL,
                  games_played INTEGER NOT NULL,
                  exact_tile_hits INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS treasure_state (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS inventory_state (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  payload TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS factory_state (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  payload TEXT NOT NULL
                );
                """
            )
            setMetaValue("\(Self.schemaVersion)", for: "schema_version")
        }
    }

    private func metaValue(for key: String) -> String? {
        guard let statement = try? db.prepare("SELECT value FROM meta WHERE key = ? LIMIT 1;") else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindText(statement, index: 1, value: key)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return SQLiteDatabase.columnText(statement, index: 0)
    }

    private func setMetaValue(_ value: String, for key: String) {
        guard let statement = try? db.prepare(
            "INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        ) else { return }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindText(statement, index: 1, value: key)
        SQLiteDatabase.bindText(statement, index: 2, value: value)
        _ = sqlite3_step(statement)
    }

    // MARK: - Legacy JSON import

    private func importLegacyJSONIfNeeded() {
        guard metaValue(for: "legacy_json_imported") != "1" else { return }

        let docs = fileURL.deletingLastPathComponent()
        var importedAny = false

        if let world = JSONFileStore.load(
            WorldSaveFile.self,
            from: docs.appendingPathComponent("atlasbound-world.json")
        ), world.version == JSONFileStore.currentSchemaVersion {
            replaceWorld(
                tiles: world.tiles.map { $0.asWorldTile() },
                progress: world.progress,
                frontier: world.frontier.asFrontierState()
            )
            importedAny = true
            archiveLegacyFile(named: "atlasbound-world.json")
        }

        if let activities: LegacyActivitySave = JSONFileStore.load(
            LegacyActivitySave.self,
            from: docs.appendingPathComponent("atlasbound-activities.json")
        ), activities.version == JSONFileStore.currentSchemaVersion {
            replaceActivities(activities)
            importedAny = true
            archiveLegacyFile(named: "atlasbound-activities.json")
        }

        if let regions: LegacyRegionSave = JSONFileStore.load(
            LegacyRegionSave.self,
            from: docs.appendingPathComponent("atlasbound-regions.json")
        ), regions.version == JSONFileStore.currentSchemaVersion {
            replaceRegionCells(regions.cells)
            importedAny = true
            archiveLegacyFile(named: "atlasbound-regions.json")
        }

        if let pinpoint: LegacyPinpointSave = JSONFileStore.load(
            LegacyPinpointSave.self,
            from: docs.appendingPathComponent("atlasbound-pinpoint.json")
        ), pinpoint.version == JSONFileStore.currentSchemaVersion {
            replacePinpoint(
                games: pinpoint.games,
                highScoreWorldwide: pinpoint.highScoreWorldwide,
                highScoreHomeTurf: pinpoint.highScoreHomeTurf,
                gamesPlayed: pinpoint.gamesPlayed ?? pinpoint.games.count,
                exactTileHits: pinpoint.exactTileHits
            )
            importedAny = true
            archiveLegacyFile(named: "atlasbound-pinpoint.json")
        }

        if let treasure: LegacyTreasureSave = JSONFileStore.load(
            LegacyTreasureSave.self,
            from: docs.appendingPathComponent("atlasbound-treasures.json")
        ), treasure.version == JSONFileStore.currentSchemaVersion {
            saveTreasure(
                dailyTrail: treasure.dailyTrail,
                weeklyVault: treasure.weeklyVault,
                relics: treasure.relics,
                completedTrailCount: treasure.completedTrailCount
            )
            importedAny = true
            archiveLegacyFile(named: "atlasbound-treasures.json")
        }

        if let inventory: LegacyInventorySave = JSONFileStore.load(
            LegacyInventorySave.self,
            from: docs.appendingPathComponent("atlasbound-inventory.json")
        ), inventory.version == JSONFileStore.currentSchemaVersion {
            saveInventory(inventory)
            importedAny = true
            archiveLegacyFile(named: "atlasbound-inventory.json")
        }

        if let factory: LegacyFactorySave = JSONFileStore.load(
            LegacyFactorySave.self,
            from: docs.appendingPathComponent("atlasbound-factory.json")
        ), factory.version == FactoryStore.schemaVersion {
            saveFactoryState(factory.state)
            importedAny = true
            archiveLegacyFile(named: "atlasbound-factory.json")
        }

        if importedAny {
            Self.logger.info("Imported legacy JSON saves into SQLite")
        }
        setMetaValue("1", for: "legacy_json_imported")
    }

    private func archiveLegacyFile(named name: String) {
        let source = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        let destination = source.appendingPathExtension("bak")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: source, to: destination)
    }

    // MARK: - World / tiles

    func loadWorld() -> (tiles: [String: WorldTile], progress: PersistedProgressRecord, frontier: FrontierState) {
        var tiles: [String: WorldTile] = [:]
        if let statement = try? db.prepare(
            """
            SELECT id, q, r, state, mastery_xp, visit_count, unique_visit_days,
                   activity_stamps, first_visited_at, last_visited_at, weekly_charge, region_ids
            FROM tiles;
            """
        ) {
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                let tile = decodeTile(from: statement)
                tiles[tile.id] = tile
            }
        }

        var progress = PersistedProgressRecord(
            discoveryXPTotal: 0,
            familiarityXPTotal: 0,
            activitiesCompleted: 0
        )
        if let statement = try? db.prepare(
            "SELECT discovery_xp, familiarity_xp, activities_completed FROM progress WHERE id = 1;"
        ) {
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW {
                progress = PersistedProgressRecord(
                    discoveryXPTotal: SQLiteDatabase.columnInt(statement, index: 0),
                    familiarityXPTotal: SQLiteDatabase.columnInt(statement, index: 1),
                    activitiesCompleted: SQLiteDatabase.columnInt(statement, index: 2)
                )
            }
        }

        var frontier = FrontierState.empty
        if let statement = try? db.prepare("SELECT payload FROM frontier WHERE id = 1;") {
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW,
               let payload = SQLiteDatabase.columnText(statement, index: 0),
               let data = payload.data(using: .utf8),
               let record = try? decoder.decode(PersistedFrontierRecord.self, from: data) {
                frontier = record.asFrontierState()
            }
        }

        return (tiles, progress, frontier)
    }

    func upsertTiles(_ tiles: [WorldTile]) {
        guard !tiles.isEmpty else { return }
        guard let statement = try? db.prepare(
            """
            INSERT INTO tiles(
              id, q, r, state, mastery_xp, visit_count, unique_visit_days,
              activity_stamps, first_visited_at, last_visited_at, weekly_charge, region_ids
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              q = excluded.q,
              r = excluded.r,
              state = excluded.state,
              mastery_xp = excluded.mastery_xp,
              visit_count = excluded.visit_count,
              unique_visit_days = excluded.unique_visit_days,
              activity_stamps = excluded.activity_stamps,
              first_visited_at = excluded.first_visited_at,
              last_visited_at = excluded.last_visited_at,
              weekly_charge = excluded.weekly_charge,
              region_ids = excluded.region_ids;
            """
        ) else { return }
        defer { sqlite3_finalize(statement) }

        try? db.transaction {
            for tile in tiles {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bindTile(tile, onto: statement)
                let status = sqlite3_step(statement)
                guard status == SQLITE_DONE else {
                    throw SQLiteError.stepFailed(db.sqliteMessage)
                }
            }
        }
    }

    func saveProgress(_ progress: PersistedProgressRecord) {
        guard let statement = try? db.prepare(
            """
            INSERT INTO progress(id, discovery_xp, familiarity_xp, activities_completed)
            VALUES(1, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              discovery_xp = excluded.discovery_xp,
              familiarity_xp = excluded.familiarity_xp,
              activities_completed = excluded.activities_completed;
            """
        ) else { return }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindInt(statement, index: 1, value: progress.discoveryXPTotal)
        SQLiteDatabase.bindInt(statement, index: 2, value: progress.familiarityXPTotal)
        SQLiteDatabase.bindInt(statement, index: 3, value: progress.activitiesCompleted)
        _ = sqlite3_step(statement)
    }

    func saveFrontier(_ state: FrontierState) {
        let record = PersistedFrontierRecord(from: state)
        guard let data = try? encoder.encode(record),
              let payload = String(data: data, encoding: .utf8),
              let statement = try? db.prepare(
                """
                INSERT INTO frontier(id, payload) VALUES(1, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload;
                """
              ) else { return }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindText(statement, index: 1, value: payload)
        _ = sqlite3_step(statement)
    }

    func replaceWorld(tiles: [WorldTile], progress: PersistedProgressRecord, frontier: FrontierState) {
        try? db.transaction {
            try db.execute("DELETE FROM tiles;")
            try db.execute("DELETE FROM progress;")
            try db.execute("DELETE FROM frontier;")
        }
        upsertTiles(tiles)
        saveProgress(progress)
        saveFrontier(frontier)
    }

    func clearWorld() {
        replaceWorld(
            tiles: [],
            progress: PersistedProgressRecord(
                discoveryXPTotal: 0,
                familiarityXPTotal: 0,
                activitiesCompleted: 0
            ),
            frontier: .empty
        )
    }

    func persistWorldSnapshot(
        dirtyTiles: [WorldTile],
        progress: PersistedProgressRecord?,
        frontier: FrontierState?,
        clearAllTiles: Bool = false
    ) {
        try? db.transaction {
            if clearAllTiles {
                try db.execute("DELETE FROM tiles;")
            }
        }
        upsertTiles(dirtyTiles)
        if let progress { saveProgress(progress) }
        if let frontier { saveFrontier(frontier) }
    }

    private func bindTile(_ tile: WorldTile, onto statement: OpaquePointer) {
        let stamps = (try? String(
            data: encoder.encode(tile.activityStamps.map(\.rawValue).sorted()),
            encoding: .utf8
        )) ?? "[]"
        let regionIDs = (try? String(data: encoder.encode(tile.regionIDs), encoding: .utf8)) ?? "[]"

        SQLiteDatabase.bindText(statement, index: 1, value: tile.id)
        SQLiteDatabase.bindInt(statement, index: 2, value: tile.coordinate.q)
        SQLiteDatabase.bindInt(statement, index: 3, value: tile.coordinate.r)
        SQLiteDatabase.bindInt(statement, index: 4, value: tile.state.rawValue)
        SQLiteDatabase.bindInt(statement, index: 5, value: tile.masteryXP)
        SQLiteDatabase.bindInt(statement, index: 6, value: tile.visitCount)
        SQLiteDatabase.bindInt(statement, index: 7, value: tile.uniqueVisitDays)
        SQLiteDatabase.bindText(statement, index: 8, value: stamps)
        SQLiteDatabase.bindDouble(statement, index: 9, value: tile.firstVisitedAt?.timeIntervalSince1970)
        SQLiteDatabase.bindDouble(statement, index: 10, value: tile.lastVisitedAt?.timeIntervalSince1970)
        SQLiteDatabase.bindInt(statement, index: 11, value: tile.weeklyCharge)
        SQLiteDatabase.bindText(statement, index: 12, value: regionIDs)
    }

    private func decodeTile(from statement: OpaquePointer) -> WorldTile {
        let id = SQLiteDatabase.columnText(statement, index: 0) ?? ""
        let q = SQLiteDatabase.columnInt(statement, index: 1)
        let r = SQLiteDatabase.columnInt(statement, index: 2)
        let state = TileState(rawValue: SQLiteDatabase.columnInt(statement, index: 3)) ?? .fogged
        let stampsJSON = SQLiteDatabase.columnText(statement, index: 7) ?? "[]"
        let stampsRaw = (try? decoder.decode([String].self, from: Data(stampsJSON.utf8))) ?? []
        let regionJSON = SQLiteDatabase.columnText(statement, index: 11) ?? "[]"
        let regionIDs = (try? decoder.decode([String].self, from: Data(regionJSON.utf8))) ?? []
        let first = SQLiteDatabase.columnDouble(statement, index: 8).map(Date.init(timeIntervalSince1970:))
        let last = SQLiteDatabase.columnDouble(statement, index: 9).map(Date.init(timeIntervalSince1970:))

        return WorldTile(
            id: id,
            coordinate: TileCoordinate(q: q, r: r),
            state: state,
            masteryXP: SQLiteDatabase.columnInt(statement, index: 4),
            visitCount: SQLiteDatabase.columnInt(statement, index: 5),
            uniqueVisitDays: SQLiteDatabase.columnInt(statement, index: 6),
            activityStamps: Set(stampsRaw.compactMap(ActivityType.init(rawValue:))),
            firstVisitedAt: first,
            lastVisitedAt: last,
            weeklyCharge: SQLiteDatabase.columnInt(statement, index: 10),
            regionIDs: regionIDs
        )
    }

    // MARK: - Activities

    func loadActivities() -> (
        sessions: [PersistedActivityRecord],
        longest: [ActivityType: Double],
        totalDistance: [ActivityType: Double],
        totalDuration: [ActivityType: TimeInterval],
        sessionCount: [ActivityType: Int]
    ) {
        var sessions: [PersistedActivityRecord] = []
        if let statement = try? db.prepare(
            "SELECT payload FROM activity_sessions ORDER BY started_at ASC;"
        ) {
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let payload = SQLiteDatabase.columnText(statement, index: 0),
                      let data = payload.data(using: .utf8),
                      let record = try? decoder.decode(PersistedActivityRecord.self, from: data) else {
                    continue
                }
                sessions.append(record)
            }
        }

        var longest: [ActivityType: Double] = [:]
        var totalDistance: [ActivityType: Double] = [:]
        var totalDuration: [ActivityType: TimeInterval] = [:]
        var sessionCount: [ActivityType: Int] = [:]
        if let statement = try? db.prepare(
            """
            SELECT activity, longest_distance, total_distance, total_duration, session_count
            FROM activity_aggregates;
            """
        ) {
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let raw = SQLiteDatabase.columnText(statement, index: 0),
                      let type = ActivityType(rawValue: raw) else { continue }
                longest[type] = SQLiteDatabase.columnDouble(statement, index: 1) ?? 0
                totalDistance[type] = SQLiteDatabase.columnDouble(statement, index: 2) ?? 0
                totalDuration[type] = SQLiteDatabase.columnDouble(statement, index: 3) ?? 0
                sessionCount[type] = SQLiteDatabase.columnInt(statement, index: 4)
            }
        }
        return (sessions, longest, totalDistance, totalDuration, sessionCount)
    }

    func replaceActivities(_ save: LegacyActivitySave) {
        try? db.transaction {
            try db.execute("DELETE FROM activity_sessions;")
            try db.execute("DELETE FROM activity_aggregates;")
        }
        for session in save.sessions {
            upsertActivitySession(session)
        }
        for (raw, value) in save.longestDistanceByActivity {
            guard let type = ActivityType(rawValue: raw) else { continue }
            upsertActivityAggregate(
                type: type,
                longest: value,
                totalDistance: save.totalDistanceByActivity[raw] ?? 0,
                totalDuration: save.totalDurationByActivity[raw] ?? 0,
                sessionCount: save.sessionCountByActivity[raw] ?? 0
            )
        }
        // Ensure aggregate rows exist for types only present in other maps.
        let allKeys = Set(save.longestDistanceByActivity.keys)
            .union(save.totalDistanceByActivity.keys)
            .union(save.totalDurationByActivity.keys)
            .union(save.sessionCountByActivity.keys)
        for raw in allKeys {
            guard let type = ActivityType(rawValue: raw) else { continue }
            upsertActivityAggregate(
                type: type,
                longest: save.longestDistanceByActivity[raw] ?? 0,
                totalDistance: save.totalDistanceByActivity[raw] ?? 0,
                totalDuration: save.totalDurationByActivity[raw] ?? 0,
                sessionCount: save.sessionCountByActivity[raw] ?? 0
            )
        }
    }

    func upsertActivitySession(_ record: PersistedActivityRecord) {
        guard let data = try? encoder.encode(record),
              let payload = String(data: data, encoding: .utf8),
              let statement = try? db.prepare(
                """
                INSERT INTO activity_sessions(id, payload, started_at) VALUES(?,?,?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, started_at = excluded.started_at;
                """
              ) else { return }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindText(statement, index: 1, value: record.id.uuidString)
        SQLiteDatabase.bindText(statement, index: 2, value: payload)
        SQLiteDatabase.bindDouble(statement, index: 3, value: record.startedAt.timeIntervalSince1970)
        _ = sqlite3_step(statement)
    }

    func replaceActivitySessions(_ sessions: [PersistedActivityRecord]) {
        try? db.execute("DELETE FROM activity_sessions;")
        for session in sessions {
            upsertActivitySession(session)
        }
    }

    func upsertActivityAggregate(
        type: ActivityType,
        longest: Double,
        totalDistance: Double,
        totalDuration: TimeInterval,
        sessionCount: Int
    ) {
        guard let statement = try? db.prepare(
            """
            INSERT INTO activity_aggregates(
              activity, longest_distance, total_distance, total_duration, session_count
            ) VALUES(?,?,?,?,?)
            ON CONFLICT(activity) DO UPDATE SET
              longest_distance = excluded.longest_distance,
              total_distance = excluded.total_distance,
              total_duration = excluded.total_duration,
              session_count = excluded.session_count;
            """
        ) else { return }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindText(statement, index: 1, value: type.rawValue)
        SQLiteDatabase.bindDouble(statement, index: 2, value: longest)
        SQLiteDatabase.bindDouble(statement, index: 3, value: totalDistance)
        SQLiteDatabase.bindDouble(statement, index: 4, value: totalDuration)
        SQLiteDatabase.bindInt(statement, index: 5, value: sessionCount)
        _ = sqlite3_step(statement)
    }

    // MARK: - Regions

    func loadRegionCells() -> [String: PersistedRegionCell] {
        var cells: [String: PersistedRegionCell] = [:]
        guard let statement = try? db.prepare(
            """
            SELECT cell_key, country_code, country_name, administrative_area, locality, resolved_at, failed_at
            FROM region_cells;
            """
        ) else { return cells }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let key = SQLiteDatabase.columnText(statement, index: 0) ?? ""
            let cell = PersistedRegionCell(
                cellKey: key,
                countryCode: SQLiteDatabase.columnText(statement, index: 1),
                countryName: SQLiteDatabase.columnText(statement, index: 2),
                administrativeArea: SQLiteDatabase.columnText(statement, index: 3),
                locality: SQLiteDatabase.columnText(statement, index: 4),
                resolvedAt: SQLiteDatabase.columnDouble(statement, index: 5).map(Date.init(timeIntervalSince1970:)),
                failedAt: SQLiteDatabase.columnDouble(statement, index: 6).map(Date.init(timeIntervalSince1970:))
            )
            cells[key] = cell
        }
        return cells
    }

    func replaceRegionCells(_ cells: [PersistedRegionCell]) {
        try? db.execute("DELETE FROM region_cells;")
        for cell in cells {
            upsertRegionCell(cell)
        }
    }

    func upsertRegionCell(_ cell: PersistedRegionCell) {
        guard let statement = try? db.prepare(
            """
            INSERT INTO region_cells(
              cell_key, country_code, country_name, administrative_area, locality, resolved_at, failed_at
            ) VALUES(?,?,?,?,?,?,?)
            ON CONFLICT(cell_key) DO UPDATE SET
              country_code = excluded.country_code,
              country_name = excluded.country_name,
              administrative_area = excluded.administrative_area,
              locality = excluded.locality,
              resolved_at = excluded.resolved_at,
              failed_at = excluded.failed_at;
            """
        ) else { return }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindText(statement, index: 1, value: cell.cellKey)
        SQLiteDatabase.bindText(statement, index: 2, value: cell.countryCode)
        SQLiteDatabase.bindText(statement, index: 3, value: cell.countryName)
        SQLiteDatabase.bindText(statement, index: 4, value: cell.administrativeArea)
        SQLiteDatabase.bindText(statement, index: 5, value: cell.locality)
        SQLiteDatabase.bindDouble(statement, index: 6, value: cell.resolvedAt?.timeIntervalSince1970)
        SQLiteDatabase.bindDouble(statement, index: 7, value: cell.failedAt?.timeIntervalSince1970)
        _ = sqlite3_step(statement)
    }

    // MARK: - Pinpoint

    func loadPinpoint() -> (
        games: [PinpointGame],
        highScoreWorldwide: Int,
        highScoreHomeTurf: Int,
        gamesPlayed: Int,
        exactTileHits: Int
    ) {
        var games: [PinpointGame] = []
        if let statement = try? db.prepare(
            "SELECT payload FROM pinpoint_games ORDER BY ended_at ASC;"
        ) {
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let payload = SQLiteDatabase.columnText(statement, index: 0),
                      let data = payload.data(using: .utf8),
                      let game = try? decoder.decode(PinpointGame.self, from: data) else { continue }
                games.append(game)
            }
        }

        var highWW = 0
        var highHT = 0
        var played = 0
        var exact = 0
        if let statement = try? db.prepare(
            """
            SELECT high_score_worldwide, high_score_home_turf, games_played, exact_tile_hits
            FROM pinpoint_stats WHERE id = 1;
            """
        ) {
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW {
                highWW = SQLiteDatabase.columnInt(statement, index: 0)
                highHT = SQLiteDatabase.columnInt(statement, index: 1)
                played = SQLiteDatabase.columnInt(statement, index: 2)
                exact = SQLiteDatabase.columnInt(statement, index: 3)
            }
        }
        return (games, highWW, highHT, played, exact)
    }

    func replacePinpoint(
        games: [PinpointGame],
        highScoreWorldwide: Int,
        highScoreHomeTurf: Int,
        gamesPlayed: Int,
        exactTileHits: Int
    ) {
        try? db.execute("DELETE FROM pinpoint_games;")
        for game in games {
            upsertPinpointGame(game)
        }
        savePinpointStats(
            highScoreWorldwide: highScoreWorldwide,
            highScoreHomeTurf: highScoreHomeTurf,
            gamesPlayed: gamesPlayed,
            exactTileHits: exactTileHits
        )
    }

    func upsertPinpointGame(_ game: PinpointGame) {
        guard let data = try? encoder.encode(game),
              let payload = String(data: data, encoding: .utf8),
              let statement = try? db.prepare(
                """
                INSERT INTO pinpoint_games(id, payload, ended_at) VALUES(?,?,?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, ended_at = excluded.ended_at;
                """
              ) else { return }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindText(statement, index: 1, value: game.id.uuidString)
        SQLiteDatabase.bindText(statement, index: 2, value: payload)
        SQLiteDatabase.bindDouble(statement, index: 3, value: game.completedAt.timeIntervalSince1970)
        _ = sqlite3_step(statement)
    }

    func savePinpointStats(
        highScoreWorldwide: Int,
        highScoreHomeTurf: Int,
        gamesPlayed: Int,
        exactTileHits: Int
    ) {
        guard let statement = try? db.prepare(
            """
            INSERT INTO pinpoint_stats(
              id, high_score_worldwide, high_score_home_turf, games_played, exact_tile_hits
            ) VALUES(1,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              high_score_worldwide = excluded.high_score_worldwide,
              high_score_home_turf = excluded.high_score_home_turf,
              games_played = excluded.games_played,
              exact_tile_hits = excluded.exact_tile_hits;
            """
        ) else { return }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindInt(statement, index: 1, value: highScoreWorldwide)
        SQLiteDatabase.bindInt(statement, index: 2, value: highScoreHomeTurf)
        SQLiteDatabase.bindInt(statement, index: 3, value: gamesPlayed)
        SQLiteDatabase.bindInt(statement, index: 4, value: exactTileHits)
        _ = sqlite3_step(statement)
    }

    // MARK: - Treasure / inventory / factory blobs

    func loadTreasure() -> LegacyTreasureSave? {
        loadBlob(table: "treasure_state", as: LegacyTreasureSave.self)
    }

    func saveTreasure(
        dailyTrail: TreasureTrail?,
        weeklyVault: WeeklyVaultState,
        relics: [RelicRecord],
        completedTrailCount: Int
    ) {
        saveBlob(
            table: "treasure_state",
            value: LegacyTreasureSave(
                version: JSONFileStore.currentSchemaVersion,
                dailyTrail: dailyTrail,
                weeklyVault: weeklyVault,
                relics: relics,
                completedTrailCount: completedTrailCount
            )
        )
    }

    func loadInventory() -> LegacyInventorySave? {
        loadBlob(table: "inventory_state", as: LegacyInventorySave.self)
    }

    func saveInventory(_ save: LegacyInventorySave) {
        saveBlob(table: "inventory_state", value: save)
    }

    func loadFactoryState() -> FactoryState? {
        guard let save = loadBlob(table: "factory_state", as: LegacyFactorySave.self),
              save.version == FactoryStore.schemaVersion else {
            return nil
        }
        return save.state
    }

    func saveFactoryState(_ state: FactoryState) {
        saveBlob(
            table: "factory_state",
            value: LegacyFactorySave(version: FactoryStore.schemaVersion, state: state)
        )
    }

    private func loadBlob<T: Decodable>(table: String, as type: T.Type) -> T? {
        guard let statement = try? db.prepare("SELECT payload FROM \(table) WHERE id = 1;") else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let payload = SQLiteDatabase.columnText(statement, index: 0),
              let data = payload.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func saveBlob<T: Encodable>(table: String, value: T) {
        guard let data = try? encoder.encode(value),
              let payload = String(data: data, encoding: .utf8),
              let statement = try? db.prepare(
                """
                INSERT INTO \(table)(id, payload) VALUES(1, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload;
                """
              ) else { return }
        defer { sqlite3_finalize(statement) }
        SQLiteDatabase.bindText(statement, index: 1, value: payload)
        _ = sqlite3_step(statement)
    }
}

// MARK: - Legacy JSON shapes (migration + blob codec)

struct LegacyActivitySave: Codable {
    var version: Int
    var sessions: [PersistedActivityRecord]
    var longestDistanceByActivity: [String: Double]
    var totalDistanceByActivity: [String: Double]
    var totalDurationByActivity: [String: Double]
    var sessionCountByActivity: [String: Int]
}

struct LegacyRegionSave: Codable {
    var version: Int
    var cells: [PersistedRegionCell]
}

struct LegacyPinpointSave: Codable {
    var version: Int
    let games: [PinpointGame]
    let highScoreWorldwide: Int
    let highScoreHomeTurf: Int
    let exactTileHits: Int
    let gamesPlayed: Int?
}

struct LegacyTreasureSave: Codable {
    var version: Int
    var dailyTrail: TreasureTrail?
    var weeklyVault: WeeklyVaultState
    var relics: [RelicRecord]
    var completedTrailCount: Int
}

struct LegacyInventorySave: Codable {
    var version: Int
    var stacks: [InventoryStack]
    var claimedFindIDs: [String]
    var claimedFindDayKey: String
    var findsClaimedToday: Int
    var activeEffects: [ActiveItemEffect]
    var cartographerPins: [CartographerPin]
    var lifetimeFindsCollected: Int
}

struct LegacyFactorySave: Codable {
    let version: Int
    let state: FactoryState
}
