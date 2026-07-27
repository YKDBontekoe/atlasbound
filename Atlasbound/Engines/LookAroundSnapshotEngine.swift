import CoreGraphics
import CoreLocation
import MapKit
import UIKit

/// Cardinal/street-scale probe used to gather distinct Look Around viewpoints
/// near a Pinpoint spawn. MapKit's snapshotter has no heading API, so nearby
/// coordinates are the way to get multiple static frames.
struct LookAroundGalleryProbe: Sendable, Equatable {
    var latitudeOffsetMeters: Double
    var longitudeOffsetMeters: Double

    static let north = LookAroundGalleryProbe(latitudeOffsetMeters: 20, longitudeOffsetMeters: 0)
    static let east = LookAroundGalleryProbe(latitudeOffsetMeters: 0, longitudeOffsetMeters: 20)
    static let south = LookAroundGalleryProbe(latitudeOffsetMeters: -20, longitudeOffsetMeters: 0)
    static let west = LookAroundGalleryProbe(latitudeOffsetMeters: 0, longitudeOffsetMeters: -20)

    static let northEast = LookAroundGalleryProbe(latitudeOffsetMeters: 20, longitudeOffsetMeters: 20)
    static let southEast = LookAroundGalleryProbe(latitudeOffsetMeters: -20, longitudeOffsetMeters: 20)
    static let southWest = LookAroundGalleryProbe(latitudeOffsetMeters: -20, longitudeOffsetMeters: -20)
    static let northWest = LookAroundGalleryProbe(latitudeOffsetMeters: 20, longitudeOffsetMeters: -20)

    static let farNorth = LookAroundGalleryProbe(latitudeOffsetMeters: 40, longitudeOffsetMeters: 0)
    static let farEast = LookAroundGalleryProbe(latitudeOffsetMeters: 0, longitudeOffsetMeters: 40)
    static let farSouth = LookAroundGalleryProbe(latitudeOffsetMeters: -40, longitudeOffsetMeters: 0)
    static let farWest = LookAroundGalleryProbe(latitudeOffsetMeters: 0, longitudeOffsetMeters: -40)

    /// Spawn first, then near cardinals, diagonals, and a farther ring.
    static let defaultProbes: [LookAroundGalleryProbe] = [
        LookAroundGalleryProbe(latitudeOffsetMeters: 0, longitudeOffsetMeters: 0),
        .north, .east, .south, .west,
        .northEast, .southEast, .southWest, .northWest,
        .farNorth, .farEast, .farSouth, .farWest
    ]
}

/// Pure helper for rendering spoiler-free Look Around imagery via MapKit snapshots.
struct LookAroundSnapshotEngine: Sendable {
    static let maxGalleryImages = 8
    static let galleryProbeDistanceMeters: Double = 20

    /// Offset a coordinate by meters north/east (negative = south/west).
    static func coordinate(
        from anchor: CLLocationCoordinate2D,
        latitudeOffsetMeters: Double,
        longitudeOffsetMeters: Double
    ) -> CLLocationCoordinate2D {
        let metersPerDegreeLat = 111_320.0
        let latRadians = anchor.latitude * .pi / 180
        let metersPerDegreeLon = max(metersPerDegreeLat * cos(latRadians), 1)

        let latitude = max(-85, min(85, anchor.latitude + latitudeOffsetMeters / metersPerDegreeLat))
        let longitude = anchor.longitude + longitudeOffsetMeters / metersPerDegreeLon
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func probeCoordinates(
        around anchor: CLLocationCoordinate2D,
        probes: [LookAroundGalleryProbe] = LookAroundGalleryProbe.defaultProbes
    ) -> [CLLocationCoordinate2D] {
        probes.map {
            coordinate(
                from: anchor,
                latitudeOffsetMeters: $0.latitudeOffsetMeters,
                longitudeOffsetMeters: $0.longitudeOffsetMeters
            )
        }
    }

    func snapshot(
        for scene: MKLookAroundScene,
        size: CGSize
    ) async throws -> UIImage {
        let options = MKLookAroundSnapshotter.Options()
        options.size = size
        options.pointOfInterestFilter = .excludingAll

        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        let snapshot = try await snapshotter.snapshot
        return snapshot.image
    }

    /// Capture up to `maxGalleryImages` static Look Around frames near `coordinate`.
    /// Failures for individual probes are skipped; an empty array means none succeeded.
    func gallerySnapshots(
        around coordinate: CLLocationCoordinate2D,
        size: CGSize,
        probes: [LookAroundGalleryProbe] = LookAroundGalleryProbe.defaultProbes,
        maxImages: Int = LookAroundSnapshotEngine.maxGalleryImages
    ) async -> [UIImage] {
        guard size.width > 1, size.height > 1, maxImages > 0 else { return [] }

        let candidates = Self.probeCoordinates(around: coordinate, probes: probes)
        var images: [UIImage] = []

        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let image = await self.snapshotIfAvailable(at: candidate, size: size)
                    return (index, image)
                }
            }

            var ordered: [(Int, UIImage)] = []
            for await (index, image) in group {
                if let image {
                    ordered.append((index, image))
                }
            }
            images = ordered
                .sorted { $0.0 < $1.0 }
                .prefix(maxImages)
                .map(\.1)
        }

        return images
    }

    private func snapshotIfAvailable(
        at coordinate: CLLocationCoordinate2D,
        size: CGSize
    ) async -> UIImage? {
        do {
            let request = MKLookAroundSceneRequest(coordinate: coordinate)
            guard let scene = try await request.scene else { return nil }
            return try await snapshot(for: scene, size: size)
        } catch {
            return nil
        }
    }
}
