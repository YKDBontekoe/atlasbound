import SwiftUI
import MapKit

/// Interactive Look Around surface with Pinpoint's map presentation preferences.
struct PinpointLookAroundView: UIViewControllerRepresentable {
    let scene: MKLookAroundScene

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let controller = MKLookAroundViewController(scene: scene)
        configure(controller)
        return controller
    }

    func updateUIViewController(_ controller: MKLookAroundViewController, context: Context) {
        controller.scene = scene
        configure(controller)
    }

    private func configure(_ controller: MKLookAroundViewController) {
        controller.isNavigationEnabled = true
        controller.showsRoadLabels = false
        controller.pointOfInterestFilter = .excludingAll
        controller.badgePosition = .topTrailing
    }
}
