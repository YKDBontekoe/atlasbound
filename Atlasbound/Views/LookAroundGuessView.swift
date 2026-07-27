import SwiftUI
import MapKit

/// Displays the Look Around scene and a slide-up guess map for one round.
struct LookAroundGuessView: View {
    let target: CLLocationCoordinate2D
    let mode: PinpointGameMode
    let roundIndex: Int
    let totalRounds: Int
    let currentScore: Int
    let roundSeconds: Int
    let regionConstraint: MKCoordinateRegion?
    let onGuess: (CLLocationCoordinate2D) -> Void

    @State private var lookAroundScene: MKLookAroundScene?
    @State private var isLoadingScene = true
    @State private var sceneUnavailable = false
    @State private var showGuessMap = false
    @State private var showLookAroundViewer = false
    @State private var guessCoordinate: CLLocationCoordinate2D?
    @State private var secondsRemaining: Int
    @State private var timerActive = false

    init(
        target: CLLocationCoordinate2D,
        mode: PinpointGameMode,
        roundIndex: Int,
        totalRounds: Int,
        currentScore: Int,
        roundSeconds: Int,
        regionConstraint: MKCoordinateRegion? = nil,
        onGuess: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.target = target
        self.mode = mode
        self.roundIndex = roundIndex
        self.totalRounds = totalRounds
        self.currentScore = currentScore
        self.roundSeconds = roundSeconds
        self.regionConstraint = regionConstraint
        self.onGuess = onGuess
        _secondsRemaining = State(initialValue: roundSeconds)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isLoadingScene {
                loadingView
            } else if sceneUnavailable {
                unavailableView
            } else if let scene = lookAroundScene {
                LookAroundPreview(
                    initialScene: scene,
                    allowsNavigation: true,
                    showsRoadLabels: false
                )
                .ignoresSafeArea()
                .lookAroundViewer(
                    isPresented: $showLookAroundViewer,
                    initialScene: scene,
                    allowsNavigation: true,
                    showsRoadLabels: false
                )
            }

            VStack(spacing: 0) {
                roundHeader
                Spacer()
                if showGuessMap {
                    guessMapOverlay
                } else {
                    bottomControls
                }
            }
        }
        .task { await loadScene() }
        .onChange(of: isLoadingScene) { _, loading in
            if !loading, !sceneUnavailable {
                timerActive = true
            }
        }
        .onChange(of: showGuessMap) { _, showing in
            timerActive = !showing && !isLoadingScene && !sceneUnavailable
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard timerActive, secondsRemaining > 0 else { return }
            secondsRemaining -= 1
            if secondsRemaining == 0 {
                withAnimation(.spring(response: 0.35)) {
                    showGuessMap = true
                }
            }
        }
    }

    private var roundHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Round \(roundIndex + 1)/\(totalRounds)")
                    .font(.headline.weight(.bold))
                if mode == .homeTurf {
                    Text("Home Turf")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AtlasTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AtlasTheme.gold.opacity(0.15), in: Capsule())
                }
            }
            Spacer()
            timerRing
            Text("\(currentScore) pts")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AtlasTheme.teal)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var timerRing: some View {
        let progress = Double(secondsRemaining) / Double(max(roundSeconds, 1))
        let urgent = secondsRemaining <= 10

        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    urgent ? AtlasTheme.finishRed : AtlasTheme.blue,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(secondsRemaining)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(urgent ? AtlasTheme.finishRed : .primary)
        }
        .frame(width: 40, height: 40)
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

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if lookAroundScene != nil {
                Button {
                    showLookAroundViewer = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text("Explore Street View")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(GlassButtonStyle(shape: .capsule))
                .padding(.horizontal, 20)
            }

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
    }

    private var guessMapOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .homeTurf ? "Guess within your atlas" : "Tap the map to guess")
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
                GuessMapView(
                    guessCoordinate: $guessCoordinate,
                    regionConstraint: regionConstraint
                )
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
