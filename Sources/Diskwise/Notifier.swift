import Foundation
import DiskwiseCore
import UserNotifications

/// The low space notification. Needs the app bundle (not the bare binary).
enum Notifier {
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func lowSpace(_ disk: DiskInfo) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your disk is almost full"
        content.body = "Only \(Bytes.format(disk.available)) left on \(disk.name). Open Diskwise in the menu bar to free up space."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-space", content: content, trigger: nil))
    }
}
