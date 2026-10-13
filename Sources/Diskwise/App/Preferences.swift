import Foundation
import ServiceManagement
import DiskwiseCore

/// User settings, stored in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    @Published var showMenuBarItem: Bool {
        didSet {
            defaults.set(showMenuBarItem, forKey: "showMenuBarItem")
            NotificationCenter.default.post(name: .menuBarItemSettingChanged, object: nil)
        }
    }
    /// Notify when available space drops under this many GB.
    @Published var alertThresholdGB: Int { didSet { defaults.set(alertThresholdGB, forKey: "alertThresholdGB") } }
    /// Folders Diskwise never lists or removes anything from.
    @Published var excludedPaths: [String] {
        didSet {
            defaults.set(excludedPaths, forKey: "excludedPaths")
            SafeDelete.excluded = excludedPaths
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { if launchAtLogin != LoginItem.isEnabled { LoginItem.set(launchAtLogin) } }
    }

    private init() {
        onboardingDone = defaults.bool(forKey: "onboardingDone")
        showMenuBarItem = defaults.object(forKey: "showMenuBarItem") as? Bool ?? true
        alertThresholdGB = defaults.object(forKey: "alertThresholdGB") as? Int ?? 10
        excludedPaths = defaults.stringArray(forKey: "excludedPaths") ?? []
        launchAtLogin = LoginItem.isEnabled
        SafeDelete.excluded = excludedPaths
    }
}

extension Notification.Name {
    static let menuBarItemSettingChanged = Notification.Name("menuBarItemSettingChanged")
}

/// Open at login through SMAppService (needs the app bundle; a bare dev binary can't register).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Diskwise: couldn't change the login item: \(error.localizedDescription)")
        }
    }
}
