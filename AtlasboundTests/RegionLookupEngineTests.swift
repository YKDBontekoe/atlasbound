import XCTest
import CoreLocation
@testable import Atlasbound

final class RegionLookupEngineTests: XCTestCase {
    func testCellKeyQuantizesNearbyCoordinates() {
        let a = CLLocationCoordinate2D(latitude: 51.8123, longitude: 4.6631)
        let b = CLLocationCoordinate2D(latitude: 51.8135, longitude: 4.6640)
        XCTAssertEqual(
            RegionLookupEngine.cellKey(for: a),
            RegionLookupEngine.cellKey(for: b)
        )
    }

    func testCellKeySeparatesDistantCoordinates() {
        let a = CLLocationCoordinate2D(latitude: 51.80, longitude: 4.66)
        let b = CLLocationCoordinate2D(latitude: 52.10, longitude: 5.10)
        XCTAssertNotEqual(
            RegionLookupEngine.cellKey(for: a),
            RegionLookupEngine.cellKey(for: b)
        )
    }

    func testRepresentativeCoordinateRoundTripsCellKey() {
        let original = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let key = RegionLookupEngine.cellKey(for: original)
        guard let restored = RegionLookupEngine.representativeCoordinate(forCellKey: key) else {
            return XCTFail("Expected representative coordinate for \(key)")
        }
        let parts = key.split(separator: ":").compactMap { Double($0) }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(restored.latitude, parts[0], accuracy: 0.0001)
        XCTAssertEqual(restored.longitude, parts[1], accuracy: 0.0001)
    }

    func testLabelsFromPlacemarkFields() {
        let labels = RegionLookupEngine.labels(
            countryCode: " nl ",
            countryName: " Netherlands ",
            administrativeArea: " Zuid-Holland ",
            locality: " Dordrecht "
        )
        XCTAssertEqual(labels.countryCode, "nl")
        XCTAssertEqual(labels.countryDisplayName, "Netherlands")
        XCTAssertEqual(labels.administrativeArea, "Zuid-Holland")
        XCTAssertEqual(labels.locality, "Dordrecht")
        XCTAssertEqual(labels.countryKey, "iso:NL")
    }

    func testPlacesVisitedAggregatesUniquePlacesByTileCount() {
        let dutch = RegionLookupEngine.labels(
            countryCode: "NL",
            countryName: "Netherlands",
            administrativeArea: "Zuid-Holland",
            locality: "Dordrecht"
        )
        let dutchOtherCity = RegionLookupEngine.labels(
            countryCode: "NL",
            countryName: "Netherlands",
            administrativeArea: "Zuid-Holland",
            locality: "Rotterdam"
        )
        let belgian = RegionLookupEngine.labels(
            countryCode: "BE",
            countryName: "Belgium",
            administrativeArea: "Antwerp",
            locality: "Antwerp"
        )

        let summary = RegionLookupEngine.placesVisited(
            cellLabels: [
                "51.80:4.66": dutch,
                "51.92:4.48": dutchOtherCity,
                "51.22:4.40": belgian
            ],
            tileCountsByCell: [
                "51.80:4.66": 5,
                "51.92:4.48": 3,
                "51.22:4.40": 2
            ]
        )

        XCTAssertEqual(summary.countries.map(\.name), ["Netherlands", "Belgium"])
        XCTAssertEqual(summary.countries.map(\.tileCount), [8, 2])
        XCTAssertEqual(summary.provinces.count, 2)
        XCTAssertEqual(summary.cities.first?.name, "Dordrecht")
        XCTAssertEqual(summary.cities.first?.tileCount, 5)
        XCTAssertEqual(summary.cities.count, 3)
    }

    func testPlacesVisitedIgnoresEmptyLabelsAndZeroTiles() {
        let empty = RegionLookupEngine.PlaceLabels(
            countryCode: nil,
            countryName: nil,
            administrativeArea: nil,
            locality: nil
        )
        let labeled = RegionLookupEngine.labels(
            countryCode: "US",
            countryName: "United States",
            administrativeArea: "California",
            locality: "San Francisco"
        )
        let summary = RegionLookupEngine.placesVisited(
            cellLabels: [
                "37.78:-122.42": labeled,
                "0.00:0.00": empty
            ],
            tileCountsByCell: [
                "37.78:-122.42": 0,
                "0.00:0.00": 4
            ]
        )
        XCTAssertTrue(summary.isEmpty)
    }

    func testTileCountsByCellGroupsNearbyTiles() {
        let engine = TileEngine(tileSizeMeters: 80)
        let origin = engine.centerCoordinate(for: TileCoordinate(q: 0, r: 0))
        // Neighbor hexes are far closer than the 0.02° cell, so they share a key.
        let tiles = [
            makeTile(size: 80, q: 0, r: 0),
            makeTile(size: 80, q: 1, r: 0),
            makeTile(size: 80, q: 0, r: 1)
        ]
        let counts = RegionLookupEngine.tileCountsByCell(tilesBySize: [80: tiles])
        XCTAssertEqual(counts.values.reduce(0, +), 3)
        XCTAssertEqual(counts[RegionLookupEngine.cellKey(for: origin)], 3)
    }

    func testStatsEnginePlacesVisitedWrapper() {
        let labels = RegionLookupEngine.labels(
            countryCode: "JP",
            countryName: "Japan",
            administrativeArea: "Tokyo",
            locality: "Shibuya"
        )
        let summary = StatsEngine.placesVisited(
            cellLabels: ["35.66:139.70": labels],
            tileCountsByCell: ["35.66:139.70": 4]
        )
        XCTAssertEqual(summary.countries.first?.name, "Japan")
        XCTAssertEqual(summary.cities.first?.tileCount, 4)
    }

    private func makeTile(size: Int, q: Int, r: Int) -> WorldTile {
        WorldTile(
            id: TileEngine.makeTileID(q: q, r: r, sizeMeters: Double(size)),
            coordinate: TileCoordinate(q: q, r: r),
            state: .discovered
        )
    }
}

@MainActor
final class RegionLookupStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-regions-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        tempURL = nil
        super.tearDown()
    }

    func testPersistsSuccessfulCellsAcrossReload() throws {
        let labels = RegionLookupEngine.labels(
            countryCode: "NL",
            countryName: "Netherlands",
            administrativeArea: "Zuid-Holland",
            locality: "Dordrecht"
        )
        let cell = PersistedRegionCell(
            cellKey: "51.80:4.66",
            labels: labels,
            resolvedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(RegionSaveFileStub(cells: [cell]))
        try data.write(to: tempURL)

        let reloaded = RegionLookupStore(fileURL: tempURL)
        XCTAssertEqual(reloaded.resolvedCellCount, 1)
        XCTAssertEqual(reloaded.successfulLabels["51.80:4.66"]?.countryDisplayName, "Netherlands")
        XCTAssertEqual(reloaded.successfulLabels["51.80:4.66"]?.locality, "Dordrecht")
    }

    func testPlacesVisitedUsesCachedLabelsForMatchingCells() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let engine = TileEngine(tileSizeMeters: 80)
        let center = engine.centerCoordinate(for: TileCoordinate(q: 0, r: 0))
        let key = RegionLookupEngine.cellKey(for: center)
        let labels = RegionLookupEngine.labels(
            countryCode: "NL",
            countryName: "Netherlands",
            administrativeArea: "Zuid-Holland",
            locality: "Dordrecht"
        )
        let cell = PersistedRegionCell(cellKey: key, labels: labels, resolvedAt: Date())
        try? encoder.encode(RegionSaveFileStub(cells: [cell])).write(to: tempURL)

        let store = RegionLookupStore(fileURL: tempURL)
        let tile = WorldTile(
            id: TileEngine.makeTileID(q: 0, r: 0, sizeMeters: 80),
            coordinate: TileCoordinate(q: 0, r: 0),
            state: .discovered
        )
        let summary = store.placesVisited(tilesBySize: [80: [tile]])
        XCTAssertEqual(summary.countries.map(\.name), ["Netherlands"])
        XCTAssertEqual(summary.provinces.map(\.name), ["Zuid-Holland"])
        XCTAssertEqual(summary.cities.map(\.name), ["Dordrecht"])
        XCTAssertEqual(summary.countries.first?.tileCount, 1)
    }
}

/// Mirrors RegionLookupStore.SaveFile for test fixture writes.
private struct RegionSaveFileStub: Codable {
    var cells: [PersistedRegionCell]
}
