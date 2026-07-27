import GameKit

/// Handles Game Center authentication and leaderboard submission.
@MainActor
final class GameCenterManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var localPlayerName: String = ""
    @Published private(set) var authError: String?

    static let leaderboardID = "com.atlasbound.geoguessr.highscore"

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.authError = error.localizedDescription
                    self.isAuthenticated = false
                    return
                }
                if viewController != nil {
                    // System presents the Game Center login UI automatically.
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                self.localPlayerName = GKLocalPlayer.local.displayName
                self.authError = nil
            }
        }
    }

    func submitScore(_ score: Int) async {
        guard isAuthenticated else { return }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.leaderboardID]
            )
        } catch {
            authError = "Failed to submit score: \(error.localizedDescription)"
        }
    }

    func showLeaderboard() {
        guard isAuthenticated else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        let viewController = GKGameCenterViewController(
            leaderboardID: Self.leaderboardID,
            playerScope: .global,
            timeScope: .allTime
        )
        viewController.gameCenterDelegate = GameCenterDismissHandler.shared

        windowScene.windows.first?.rootViewController?.present(viewController, animated: true)
    }
}

/// Minimal dismiss handler for Game Center view controller.
final class GameCenterDismissHandler: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterDismissHandler()
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
