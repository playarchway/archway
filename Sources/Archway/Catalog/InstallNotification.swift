import Foundation
import UserNotifications

/// Tells the player when Steam has finished installing a game, since it downloads out of sight. macOS shows it
/// only while Archway is in the background; in front, the game's button already says so.
enum InstallNotification {
    /// Asked on the first install rather than at launch, when the reason is clear.
    static func requestPermission() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(gameID: Int, title: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Ready to Play")
        content.body = String(localized: "\(title) is installed.")
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "installed-\(gameID)", content: content, trigger: nil))
    }

    /// Notifications need an app bundle; the bare SwiftPM binary has none.
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }
}
