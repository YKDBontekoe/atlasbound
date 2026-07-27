import GameKit
import UIKit

/// Handles Game Center authentication and leaderboard submission.
@MainActor
final class GameCenterManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var localPlayerName: String = ""
    @Published private(set) var authError: String?

    static let leaderboardID = "com.atlasbound.geoguessr.highscore"

    func authenticate() {
        authError = nil
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    self.present(viewController)
                    return
                }
                if let error {
                    if Self.isExpectedUnauthenticatedError(error) {
                        self.isAuthenticated = false
                        return
                    }
                    self.authError = error.localizedDescription
                    self.isAuthenticated = false
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
            if !Self.isExpectedUnauthenticatedError(error) {
                authError = "Failed to submit score: \(error.localizedDescription)"
            }
        }
    }

    func showLeaderboard() {
        guard isAuthenticated else { return }

        let viewController = GKGameCenterViewController(
            leaderboardID: Self.leaderboardID,
            playerScope: .global,
            timeScope: .allTime
        )
        viewController.gameCenterDelegate = GameCenterDismissHandler.shared
        present(viewController)
    }

    private func present(_ viewController: UIViewController) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        rootViewController.present(viewController, animated: true)
    }

    private static func isExpectedUnauthenticatedError(_ error: Error) -> Bool {
        if let gkError = error as? GKError, gkError.code == .notAuthenticated {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("not been authenticated") || message.contains("not authenticated")
    }
}

/// Minimal dismiss handler for Game Center view controller.
final class GameCenterDismissHandler: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterDismissHandler()
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
