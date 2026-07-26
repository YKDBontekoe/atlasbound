import SwiftUI

@main
struct AtlasboundApp: App {
    @StateObject private var store = TileStore()
    @StateObject private var controllerHolder = ControllerHolder()

    var body: some Scene {
        WindowGroup {
            Group {
                if let controller = controllerHolder.controller {
                    RootTabView(controller: controller, store: store)
                } else {
                    ProgressView("Loading world…")
                }
            }
            .onAppear {
                controllerHolder.bootstrap(store: store)
            }
        }
    }
}

@MainActor
final class ControllerHolder: ObservableObject {
    @Published var controller: WorldController?

    func bootstrap(store: TileStore) {
        guard controller == nil else { return }
        controller = WorldController(store: store)
    }
}
