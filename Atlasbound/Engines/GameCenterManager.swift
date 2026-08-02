import GameKit
import UIKit

/// Handles Game Center authentication and leaderboard submission.
@MainActor
final class GameCenterManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var localPlayerName: String = ""
    @Published private(set) var authError: String?

    static let pinpointLeaderboardID = "com.atlasbound.geoguessr.highscore"

    static let frontierLeaderboardID = "com.atlasbound.frontier.weekly.20"

    func authenticate() {
        authError = nil
        isAuthenticating = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    // Keep `isAuthenticating` until GameKit finishes (or dismisses) auth UI.
                    self.present(viewController)
                    return
                }
                self.isAuthenticating = false
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
                leaderboardIDs: [Self.pinpointLeaderboardID]
            )
        } catch {
            if !Self.isExpectedUnauthenticatedError(error) {
                authError = "Failed to submit score: \(error.localizedDescription)"
            }
        }
    }

    func submitFrontierScore(_ score: Int) async {
        guard isAuthenticated, score > 0 else { return }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.frontierLeaderboardID]
            )
        } catch {
            authError = "Failed to submit frontier score: \(error.localizedDescription)"
        }
    }

    func showLeaderboard() {
        showLeaderboard(id: Self.pinpointLeaderboardID)
    }

    func showFrontierLeaderboard() {
        showLeaderboard(id: Self.frontierLeaderboardID)
    }

    private func showLeaderboard(id: String) {
        guard isAuthenticated else { return }

        let viewController = GKGameCenterViewController(
            leaderboardID: id,
            playerScope: .global,
            timeScope: .week
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
