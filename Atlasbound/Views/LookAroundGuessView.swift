import SwiftUI
import MapKit

/// Displays the Look Around scene and a slide-up guess map for one round.
struct LookAroundGuessView: View {
    let target: CLLocationCoordinate2D
    let roundIndex: Int
    let totalRounds: Int
    let currentScore: Int
    let onGuess: (CLLocationCoordinate2D) -> Void

    @State private var lookAroundScene: MKLookAroundScene?
    @State private var isLoadingScene = true
    @State private var sceneUnavailable = false
    @State private var showGuessMap = false
    @State private var guessCoordinate: CLLocationCoordinate2D?

    var body: some View {
        ZStack(alignment: .bottom) {
            if isLoadingScene {
                loadingView
            } else if sceneUnavailable {
                unavailableView
            } else if let scene = lookAroundScene {
                LookAroundPreview(initialScene: scene)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                roundHeader
                Spacer()
                if showGuessMap {
                    guessMapOverlay
                } else {
                    openGuessButton
                }
            }
        }
        .task { await loadScene() }
    }

    private var roundHeader: some View {
        HStack {
            Text("Round \(roundIndex + 1)/\(totalRounds)")
                .font(.headline.weight(.bold))
            Spacer()
            Text("\(currentScore) pts")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AtlasTheme.teal)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Loading Look Around…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Look Around not available here")
                .font(.headline)
            Text("Place your guess on the map anyway!")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showGuessMap = true
            } label: {
                Text("Open Map")
                    .font(.headline.weight(.bold))
                    .frame(width: 200, height: 48)
            }
            .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.blue, shape: .capsule))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var openGuessButton: some View {
        Button {
            withAnimation(.spring(response: 0.35)) {
                showGuessMap = true
            }
        } label: {
            HStack {
                Image(systemName: "map.fill")
                Text("Place Guess")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.blue, shape: .capsule))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var guessMapOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tap the map to guess")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35)) {
                        showGuessMap = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            ZStack(alignment: .bottom) {
                GuessMapView(guessCoordinate: $guessCoordinate)
                    .frame(height: 300)

                if guessCoordinate != nil {
                    Button {
                        if let guess = guessCoordinate {
                            onGuess(guess)
                        }
                    } label: {
                        Text("Confirm Guess")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.teal, shape: .capsule))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func loadScene() async {
        let request = MKLookAroundSceneRequest(coordinate: target)
        do {
            let scene = try await request.scene
            await MainActor.run {
                if let scene {
                    self.lookAroundScene = scene
                } else {
                    self.sceneUnavailable = true
                }
                self.isLoadingScene = false
            }
        } catch {
            await MainActor.run {
                self.sceneUnavailable = true
                self.isLoadingScene = false
            }
        }
    }
}
