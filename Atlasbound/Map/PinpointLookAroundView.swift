import SwiftUI
import MapKit

/// Interactive Look Around surface with Pinpoint's map presentation preferences.
struct PinpointLookAroundView: UIViewControllerRepresentable {
    let scene: MKLookAroundScene
    var onSceneUpdate: ((MKLookAroundScene) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onSceneUpdate: onSceneUpdate)
    }

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let controller = MKLookAroundViewController(scene: scene)
        controller.delegate = context.coordinator
        configure(controller)
        return controller
    }

    func updateUIViewController(_ controller: MKLookAroundViewController, context: Context) {
        context.coordinator.onSceneUpdate = onSceneUpdate
        controller.delegate = context.coordinator
        controller.scene = scene
        configure(controller)
    }

    private func configure(_ controller: MKLookAroundViewController) {
        // Prevent tap-to-walk along streets, which updates Apple's address badge.
        controller.isNavigationEnabled = false
        controller.showsRoadLabels = false
        controller.pointOfInterestFilter = .excludingAll
        controller.badgePosition = .topTrailing
    }

    final class Coordinator: NSObject, MKLookAroundViewControllerDelegate {
        var onSceneUpdate: ((MKLookAroundScene) -> Void)?

        init(onSceneUpdate: ((MKLookAroundScene) -> Void)?) {
            self.onSceneUpdate = onSceneUpdate
        }

        func lookAroundViewControllerDidUpdateScene(_ viewController: MKLookAroundViewController) {
            guard let scene = viewController.scene else { return }
            onSceneUpdate?(scene)
        }
    }
}
