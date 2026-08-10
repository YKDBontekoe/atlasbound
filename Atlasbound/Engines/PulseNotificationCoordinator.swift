import Foundation
import UserNotifications

/// Local notifications for already-known Pulse phase changes.
/// It never requests or reads location, and it does not replace server push.
@MainActor
final class PulseNotificationCoordinator {
    static let shared = PulseNotificationCoordinator()

    private let center = UNUserNotificationCenter.current()
    private let enabledKey = "atlasbound.pulseAlerts.enabled"

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            UserDefaults.standard.set(granted, forKey: enabledKey)
            return granted
        } catch {
            return false
        }
    }

    func schedulePeak(for pulse: AtlasPulse, at date: Date = .now) {
        guard isEnabled,
              let peak = pulse.phaseEndsAt[.peak], peak > date else { return }
        let content = UNMutableNotificationContent()
        content.title = "Atlasbound · World now"
        content.body = "(pulse.kind.title) is reaching its peak nearby."
        content.sound = .default
        content.userInfo = ["pulseID": pulse.id]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, peak.timeIntervalSince(date)),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "atlasbound.pulse.peak.\(pulse.id)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancel(for pulse: AtlasPulse) {
        center.removePendingNotificationRequests(withIdentifiers: ["atlasbound.pulse.peak.\(pulse.id)"])
    }
}

