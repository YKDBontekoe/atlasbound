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

    /// Spawn first, then near cardinals only.
    /// Keeping the default set small bounds GeoServices scene requests per round.
    static let defaultProbes: [LookAroundGalleryProbe] = [
        LookAroundGalleryProbe(latitudeOffsetMeters: 0, longitudeOffsetMeters: 0),
        .north, .east, .south, .west
    ]
}

/// Pure helper for rendering spoiler-free Look Around imagery via MapKit snapshots.
struct LookAroundSnapshotEngine: Sendable {
    /// Up to four viewpoints keep Pinpoint playable without the concurrent /
    /// 8-frame burst that exhausted GeoServices during Worldwide scouting.
    static let maxGalleryImages = 4
    static let galleryProbeDistanceMeters: Double = 20
    /// Cap decoded snapshot pixels so four frames stay memory-cheap on @3x phones.
    static let maxSnapshotPixelDimension: CGFloat = 1024
    /// After the first usable frame, stop spending GeoServices budget on extras.
    static let additionalProbeBudget: Duration = .milliseconds(2_500)

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

    /// Shrink full-screen point sizes so the decoded bitmap stays under the pixel budget.
    /// `scale` is the screen scale (`UIScreen.scale`) because MapKit renders snapshots in pixels.
    static func gallerySnapshotSize(for screen: CGSize, scale: CGFloat) -> CGSize {
        let width = max(screen.width, 1)
        let height = max(screen.height, 1)
        let safeScale = max(scale, 1)
        let longestPixels = max(width, height) * safeScale
        guard longestPixels > maxSnapshotPixelDimension else {
            return CGSize(width: width, height: height)
        }
        let factor = maxSnapshotPixelDimension / longestPixels
        return CGSize(
            width: floor(width * factor),
            height: floor(height * factor)
        )
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
    /// When `onImage` is provided, each successful frame is delivered as soon as it is ready.
    ///
    /// Performance contract:
    /// - probes run **sequentially** (never as a concurrent burst)
    /// - decode size is capped via `gallerySnapshotSize`
    /// - after the first success, extra probes stop once `additionalProbeBudget` elapses
    /// - `shouldContinue` can abort remaining probes (e.g. player opened the guess map)
    func gallerySnapshots(
        around coordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat = 3,
        probes: [LookAroundGalleryProbe] = LookAroundGalleryProbe.defaultProbes,
        maxImages: Int = LookAroundSnapshotEngine.maxGalleryImages,
        additionalProbeBudget: Duration = LookAroundSnapshotEngine.additionalProbeBudget,
        shouldContinue: (@Sendable () async -> Bool)? = nil,
        onImage: (@Sendable (UIImage) async -> Void)? = nil
    ) async -> [UIImage] {
        guard size.width > 1, size.height > 1, maxImages > 0 else { return [] }

        let renderSize = Self.gallerySnapshotSize(for: size, scale: scale)
        let candidates = Self.probeCoordinates(around: coordinate, probes: probes)
        var images: [UIImage] = []
        images.reserveCapacity(min(maxImages, candidates.count))
        var extraProbeDeadline: ContinuousClock.Instant?

        // MapKit snapshotters are expensive and do not provide a reliable
        // concurrency budget. Probing sequentially keeps peak memory and
        // GeoServices pressure bounded so Worldwide prep can keep scouting.
        for candidate in candidates {
            guard !Task.isCancelled else { return images }
            if let shouldContinue, await shouldContinue() == false {
                return images
            }
            if let deadline = extraProbeDeadline, ContinuousClock.now >= deadline {
                break
            }

            if let image = await snapshotIfAvailable(at: candidate, size: renderSize) {
                guard !Task.isCancelled else { return images }
                images.append(image)
                if images.count == 1 {
                    extraProbeDeadline = ContinuousClock.now.advanced(by: additionalProbeBudget)
                }
                if let onImage {
                    await onImage(image)
                }
                if images.count == maxImages {
                    break
                }
            }
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
