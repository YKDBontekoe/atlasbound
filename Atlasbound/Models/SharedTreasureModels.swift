import Foundation
import CoreLocation

/// A server-owned treasure destination that can be claimed by one player.
struct SharedTreasureEvent: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let tileID: String
    let latitude: Double
    let longitude: Double
    let name: String
    let category: String
    let clue: String
    let distanceMeters: Double
    let isVault: Bool
    let createdAt: Date
    let expiresAt: Date
    let claimedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, tileID = "tile_id", latitude, longitude, name, category, clue
        case distanceMeters = "distance_meters", isVault = "is_vault"
        case createdAt = "created_at", expiresAt = "expires_at"
        case claimedAt = "claimed_at"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isActive: Bool { claimedAt == nil && expiresAt > .now }

    var landmarkTarget: LandmarkTarget {
        LandmarkTarget(
            id: "shared:\(id.uuidString)",
            tileID: tileID,
            name: name,
            category: category,
            clue: clue,
            isFallback: false,
            distanceMeters: distanceMeters
        )
    }
}

struct SharedTreasureSpawnRequest: Encodable, Sendable {
    let tileID: String
    let latitude: Double
    let longitude: Double
    let isVault: Bool
    let dayKey: String

    enum CodingKeys: String, CodingKey {
        case tileID = "tile_id", latitude, longitude, isVault = "is_vault", dayKey = "day_key"
    }
}

struct SharedTreasureClaimResult: Decodable, Sendable {
    let event: SharedTreasureEvent?
    let didWin: Bool
}
