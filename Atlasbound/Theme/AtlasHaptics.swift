import UIKit

/// Discrete haptic vocabulary for Atlasbound interactions.
@MainActor
enum AtlasHaptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        softImpact.prepare()
        notification.prepare()
        selection.prepare()
    }

    static func select() {
        selection.selectionChanged()
    }

    static func light() {
        lightImpact.impactOccurred(intensity: 0.7)
    }

    static func success() {
        notification.notificationOccurred(.success)
    }

    static func discovery() {
        softImpact.impactOccurred(intensity: 0.85)
    }

    static func mastery() {
        mediumImpact.impactOccurred(intensity: 1.0)
    }
}
