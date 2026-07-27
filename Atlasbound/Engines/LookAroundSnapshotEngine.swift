import CoreGraphics
import MapKit
import UIKit

/// Camera orientation for Look Around snapshot requests.
struct LookAroundCamera: Sendable, Equatable {
    var heading: Double
    var pitch: Double

    static let `default` = LookAroundCamera(heading: 0, pitch: 0)
}

/// Pure helper for rendering spoiler-free Look Around imagery via MapKit snapshots.
struct LookAroundSnapshotEngine: Sendable {
    func snapshot(
        for scene: MKLookAroundScene,
        size: CGSize,
        camera: LookAroundCamera = .default
    ) async throws -> UIImage {
        let options = MKLookAroundSnapshotter.Options()
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        _ = camera

        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        let snapshot = try await snapshotter.snapshot
        return snapshot.image
    }
}
