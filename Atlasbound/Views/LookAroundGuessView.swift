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
    let onQuit: () -> Void

    @State private var lookAroundScene: MKLookAroundScene?
    @State private var isLoadingScene = true
    @State private var sceneUnavailable = false
    @State private var showGuessMap = false
    @State private var guessCoordinate: CLLocationCoordinate2D?
    @State private var secondsRemaining: Int
    @State private var timerActive = false
    @State private var showQuitConfirmation = false
    @State private var useInteractiveFallback = false

    init(
        target: CLLocationCoordinate2D,
        mode: PinpointGameMode,
        roundIndex: Int,
        totalRounds: Int,
        currentScore: Int,
        roundSeconds: Int,
        regionConstraint: MKCoordinateRegion? = nil,
        onGuess: @escaping (CLLocationCoordinate2D) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.target = target
        self.mode = mode
        self.roundIndex = roundIndex
        self.totalRounds = totalRounds
        self.currentScore = currentScore
        self.roundSeconds = roundSeconds
        self.regionConstraint = regionConstraint
        self.onGuess = onGuess
        self.onQuit = onQuit
        _secondsRemaining = State(initialValue: roundSeconds)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isLoadingScene {
                loadingView
            } else if sceneUnavailable {
                unavailableView
            } else if let scene = lookAroundScene {
                if useInteractiveFallback {
                    PinpointLookAroundView(scene: scene)
                        .ignoresSafeArea()
                } else {
                    LookAroundSnapshotViewer(scene: scene) {
                        useInteractiveFallback = true
                    }
                    .ignoresSafeArea()
                }

                if useInteractiveFallback {
                    spoilerGuardOverlay
                }
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
        .confirmationDialog("Leave this game?", isPresented: $showQuitConfirmation, titleVisibility: .visible) {
            Button("Leave Game", role: .destructive, action: onQuit)
            Button("Keep Playing", role: .cancel) { }
        } message: {
            Text("Your current round progress will be lost.")
        }
        .task(id: sceneRequestID) { await prepareRound() }
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
        HStack(spacing: 10) {
            Button {
                showQuitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave Pinpoint game")

            VStack(alignment: .leading, spacing: 4) {
                Text("ROUND \(roundIndex + 1) · \(totalRounds)")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text("Find your bearings")
                    .font(.subheadline.weight(.semibold))
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
            VStack(alignment: .trailing, spacing: 2) {
                Text("SCORE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(currentScore)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(AtlasTheme.teal)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
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

    private var spoilerGuardOverlay: some View {
        VStack {
            Spacer()
            HStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                    }
                    .frame(width: 150, height: 88)
                    .padding(.leading, 8)
                Spacer()
            }
            .padding(.bottom, 44)
        }
        .allowsHitTesting(false)
    }

    private var bottomControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "scope")
                Text("Lock in your best estimate")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.86))

            Button {
                withAnimation(.spring(response: 0.35)) {
                    showGuessMap = true
                }
            } label: {
                Label("Place Guess", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.plain)
            .background {
                GlassChrome(
                    shape: Capsule(),
                    weight: .regular,
                    tint: Color.black,
                    tintOpacity: 0.42
                )
            }
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .padding(.horizontal, 20)
        // Leave clear space for MapKit's required Apple Maps attribution.
        .padding(.bottom, 52)
        .background {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
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

    /// Reuse the view between rounds so MapKit can release its previous preview
    /// before requesting the next scene. Recreating the entire preview hierarchy
    /// during the result-to-round transition can make the simulator return to the
    /// app root instead of presenting the next round.
    private var sceneRequestID: String {
        "\(roundIndex):\(target.latitude):\(target.longitude)"
    }

    @MainActor
    private func prepareRound() async {
        timerActive = false
        isLoadingScene = true
        sceneUnavailable = false
        lookAroundScene = nil
        useInteractiveFallback = false
        showGuessMap = false
        guessCoordinate = nil
        secondsRemaining = roundSeconds
        await Task.yield()
        await loadScene()
    }
}
