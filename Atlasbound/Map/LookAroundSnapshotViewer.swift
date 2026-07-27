import SwiftUI
import MapKit

/// Spoiler-free Look Around viewer: interactive gestures run underneath while a
/// MapKit snapshot (no Apple address badge) is displayed on top.
struct LookAroundSnapshotViewer: View {
    let scene: MKLookAroundScene
    var onSnapshotFailed: (() -> Void)? = nil

    @State private var displayedImage: UIImage?
    @State private var activeScene: MKLookAroundScene
    @State private var snapshotTask: Task<Void, Never>?
    @State private var didFail = false

    private let engine = LookAroundSnapshotEngine()

    init(scene: MKLookAroundScene, onSnapshotFailed: (() -> Void)? = nil) {
        self.scene = scene
        self.onSnapshotFailed = onSnapshotFailed
        _activeScene = State(initialValue: scene)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PinpointLookAroundView(scene: activeScene) { updatedScene in
                    activeScene = updatedScene
                    scheduleSnapshot(size: geometry.size, scene: updatedScene)
                }
                .ignoresSafeArea()

                if let displayedImage {
                    Image(uiImage: displayedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                } else if !didFail {
                    ProgressView()
                        .controlSize(.large)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                appleMapsAttribution
            }
            .onAppear {
                scheduleSnapshot(size: geometry.size, scene: activeScene)
            }
            .onChange(of: scene) { _, newScene in
                activeScene = newScene
                scheduleSnapshot(size: geometry.size, scene: newScene)
            }
            .onChange(of: geometry.size) { _, newSize in
                scheduleSnapshot(size: newSize, scene: activeScene)
            }
            .onDisappear {
                snapshotTask?.cancel()
            }
        }
    }

    private var appleMapsAttribution: some View {
        Text("Apple Maps")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(.leading, 12)
            .padding(.bottom, 56)
            .allowsHitTesting(false)
    }

    private func scheduleSnapshot(size: CGSize, scene: MKLookAroundScene) {
        snapshotTask?.cancel()
        guard size.width > 1, size.height > 1 else { return }

        snapshotTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }

            do {
                let image = try await engine.snapshot(for: scene, size: size)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    displayedImage = image
                    didFail = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    didFail = true
                    onSnapshotFailed?()
                }
            }
        }
    }
}
