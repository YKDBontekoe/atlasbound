import SwiftUI

/// Shared motion tokens for chrome fluency and celebration moments.
enum AtlasMotion {
    /// Glass button press — snappy ease-out.
    static let press = Animation.easeOut(duration: 0.12)

    /// Idle ↔ recording chrome morph, Pinpoint phase changes.
    static let chrome = Animation.spring(response: 0.35, dampingFraction: 0.86)

    /// Panels, sheets content, expand/collapse.
    static let panel = Animation.spring(response: 0.32, dampingFraction: 0.9)

    /// Numeric counters / contentTransition companion.
    static let number = Animation.spring(response: 0.28, dampingFraction: 0.92)

    /// Score / XP / badge pop.
    static let celebrate = Animation.spring(response: 0.42, dampingFraction: 0.72)

    /// Ambient loops (beacons, urgency pulse).
    static let ambient = Animation.easeInOut(duration: 1.4)

    /// Map camera recenter.
    static let camera = Animation.easeInOut(duration: 0.35)

    /// Soft fade for layers / overlays.
    static let fade = Animation.easeOut(duration: 0.25)

    /// Toast / callout float-away.
    static let toastFade = Animation.easeOut(duration: 1.2)

    // MARK: - Reduce Motion helpers

    /// Returns `animation` unless Reduce Motion is on (then `nil`).
    static func optional(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Runs `body` inside `withAnimation` unless Reduce Motion is on (then runs immediately).
    static func withOptionalAnimation(
        _ animation: Animation,
        reduceMotion: Bool,
        _ body: () -> Void
    ) {
        if reduceMotion {
            body()
        } else {
            withAnimation(animation, body)
        }
    }
}

// MARK: - Snapshot / settled-frame override

private struct AtlasForceSettledMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When true, motion views snap to their final frame (used by snapshot tests).
    var atlasForceSettledMotion: Bool {
        get { self[AtlasForceSettledMotionKey.self] }
        set { self[AtlasForceSettledMotionKey.self] = newValue }
    }
}
