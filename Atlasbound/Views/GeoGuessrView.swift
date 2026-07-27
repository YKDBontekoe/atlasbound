import SwiftUI
import MapKit

/// Top-level GeoGuessr mode screen — lobby, active game, and results.
struct GeoGuessrView: View {
    @ObservedObject var geoStore: GeoGuessrStore
    @ObservedObject var gameCenterManager: GameCenterManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var gameState: GameState = .lobby
    @State private var targets: [CLLocationCoordinate2D] = []
    @State private var roundResults: [GeoGuessrEngine.RoundResult] = []
    @State private var currentRound = 0

    enum GameState {
        case lobby
        case playing
        case roundResult(GeoGuessrEngine.RoundResult)
        case gameOver(GeoGuessrEngine.GameResult)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch gameState {
                case .lobby:
                    lobbyView
                case .playing:
                    if currentRound < targets.count {
                        LookAroundGuessView(
                            target: targets[currentRound],
                            roundIndex: currentRound,
                            totalRounds: GeoGuessrEngine.roundsPerGame,
                            currentScore: roundResults.reduce(0) { $0 + $1.score },
                            onGuess: { guess in
                                submitGuess(guess)
                            }
                        )
                        .id("round-\(currentRound)")
                    }
                case .roundResult(let result):
                    RoundResultView(
                        result: result,
                        roundNumber: currentRound,
                        totalRounds: GeoGuessrEngine.roundsPerGame,
                        runningTotal: roundResults.reduce(0) { $0 + $1.score },
                        onNext: advanceRound
                    )
                case .gameOver(let game):
                    GameOverView(
                        game: game,
                        highScore: geoStore.highScore,
                        gameCenterManager: gameCenterManager,
                        onPlayAgain: startNewGame,
                        onBackToLobby: { gameState = .lobby }
                    )
                }
            }
            .navigationTitle("GeoGuessr")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Lobby

    private var lobbyView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AtlasTheme.blue, AtlasTheme.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("GeoGuessr")
                        .font(.largeTitle.bold())
                    Text("Guess your location from Look Around")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                VStack(spacing: 12) {
                    statsRow(icon: "star.fill", label: "High Score",
                             value: "\(geoStore.highScore) / \(GeoGuessrEngine.maxPossibleScore)",
                             tint: AtlasTheme.gold)
                    statsRow(icon: "gamecontroller.fill", label: "Games Played",
                             value: "\(geoStore.gamesPlayed)",
                             tint: AtlasTheme.blue)
                }
                .padding(16)
                .background {
                    GlassChrome(
                        shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                        weight: .regular
                    )
                }

                Button {
                    startNewGame()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Game")
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.blue, shape: .capsule))

                if gameCenterManager.isAuthenticated {
                    Button {
                        gameCenterManager.showLeaderboard()
                    } label: {
                        HStack {
                            Image(systemName: "trophy.fill")
                            Text("Leaderboard")
                                .font(.headline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                    }
                    .buttonStyle(GlassButtonStyle(shape: .capsule))
                } else {
                    Button {
                        gameCenterManager.authenticate()
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Sign in to Game Center")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(GlassButtonStyle(shape: .capsule))
                }

                if let error = gameCenterManager.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.finishRed)
                }

                if !geoStore.gameHistory.isEmpty {
                    recentGamesSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func statsRow(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())
            Text(label)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Games")
                .font(.headline)
            ForEach(geoStore.gameHistory.suffix(5).reversed()) { game in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(game.totalScore) pts")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text(game.completedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ForEach(game.rounds) { round in
                        RoundScoreDot(score: round.score)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
    }

    // MARK: - Game flow

    private func startNewGame() {
        targets = GeoGuessrEngine.generateRoundTargets()
        roundResults = []
        currentRound = 0
        gameState = .playing
    }

    private func submitGuess(_ guess: CLLocationCoordinate2D) {
        let result = GeoGuessrEngine.RoundResult(
            target: targets[currentRound],
            guess: guess,
            roundIndex: currentRound
        )
        roundResults.append(result)
        gameState = .roundResult(result)
    }

    private func advanceRound() {
        currentRound += 1
        if currentRound >= GeoGuessrEngine.roundsPerGame {
            let game = GeoGuessrEngine.GameResult(rounds: roundResults)
            geoStore.record(game)
            if gameCenterManager.isAuthenticated {
                Task {
                    await gameCenterManager.submitScore(game.totalScore)
                }
            }
            gameState = .gameOver(game)
        } else {
            gameState = .playing
        }
    }
}

// MARK: - Round score indicator

struct RoundScoreDot: View {
    let score: Int

    private var color: Color {
        if score >= 4500 { return AtlasTheme.gold }
        if score >= 3000 { return AtlasTheme.teal }
        if score >= 1000 { return AtlasTheme.blue }
        return AtlasTheme.finishRed
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Look Around + Guess Map

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
    @State private var guessMapPosition: MapCameraPosition = .automatic

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

// MARK: - Guess Map (tappable world map)

struct GuessMapView: UIViewRepresentable {
    @Binding var guessCoordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .standard
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)

        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeAnnotations(mapView.annotations)
        if let coord = guessCoordinate {
            let pin = MKPointAnnotation()
            pin.coordinate = coord
            pin.title = "Your Guess"
            mapView.addAnnotation(pin)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: GuessMapView

        init(_ parent: GuessMapView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.guessCoordinate = coordinate
        }
    }
}

// MARK: - Round Result

struct RoundResultView: View {
    let result: GeoGuessrEngine.RoundResult
    let roundNumber: Int
    let totalRounds: Int
    let runningTotal: Int
    let onNext: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                Marker("Target", systemImage: "mappin.circle.fill", coordinate: result.target)
                    .tint(AtlasTheme.teal)
                Marker("Your Guess", systemImage: "hand.point.up.fill", coordinate: result.guess)
                    .tint(AtlasTheme.finishRed)
                MapPolyline(coordinates: [result.target, result.guess])
                    .stroke(AtlasTheme.blue, lineWidth: 2)
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(maxHeight: .infinity)

            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text("\(result.score)")
                            .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(scoreColor)
                        Text("points")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 4) {
                        Text(GeoGuessrEngine.formatDistance(result.distanceMeters))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("distance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Round \(roundNumber + 1)/\(totalRounds)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Total: \(runningTotal)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }

                Button {
                    onNext()
                } label: {
                    Text(roundNumber + 1 >= totalRounds ? "See Results" : "Next Round")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.blue, shape: .capsule))
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
        .onAppear {
            let midLat = (result.target.latitude + result.guess.latitude) / 2
            let midLon = (result.target.longitude + result.guess.longitude) / 2
            let spanLat = abs(result.target.latitude - result.guess.latitude) * 1.5 + 0.5
            let spanLon = abs(result.target.longitude - result.guess.longitude) * 1.5 + 0.5
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
                span: MKCoordinateSpan(latitudeDelta: max(spanLat, 1), longitudeDelta: max(spanLon, 1))
            ))
        }
    }

    private var scoreColor: Color {
        if result.score >= 4500 { return AtlasTheme.gold }
        if result.score >= 3000 { return AtlasTheme.teal }
        if result.score >= 1000 { return AtlasTheme.blue }
        return AtlasTheme.finishRed
    }
}

// MARK: - Game Over

struct GameOverView: View {
    let game: GeoGuessrEngine.GameResult
    let highScore: Int
    let gameCenterManager: GameCenterManager
    let onPlayAgain: () -> Void
    let onBackToLobby: () -> Void

    private var isNewHighScore: Bool {
        game.totalScore >= highScore
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    if isNewHighScore {
                        Text("New High Score!")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AtlasTheme.gold)
                    }
                    Text("\(game.totalScore)")
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    Text("out of \(GeoGuessrEngine.maxPossibleScore)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                VStack(spacing: 8) {
                    ForEach(game.rounds) { round in
                        HStack {
                            Text("Round \(round.roundIndex + 1)")
                                .font(.subheadline)
                            Spacer()
                            Text(GeoGuessrEngine.formatDistance(round.distanceMeters))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(round.score) pts")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(16)
                .background {
                    GlassChrome(
                        shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                        weight: .regular
                    )
                }

                VStack(spacing: 12) {
                    Button {
                        onPlayAgain()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Play Again")
                                .font(.headline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.blue, shape: .capsule))

                    if gameCenterManager.isAuthenticated {
                        Button {
                            gameCenterManager.showLeaderboard()
                        } label: {
                            HStack {
                                Image(systemName: "trophy.fill")
                                Text("Leaderboard")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                        }
                        .buttonStyle(GlassButtonStyle(shape: .capsule))
                    }

                    Button {
                        onBackToLobby()
                    } label: {
                        Text("Back to Menu")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}
