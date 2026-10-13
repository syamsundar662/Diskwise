import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

/// Thin wrapper around Sparkle's standard updater controller.
///
/// `swift build`/`swift test` build Sources/Diskwise without Sparkle (see
/// Package.swift), so every Sparkle type below is behind `canImport(Sparkle)`.
/// In that configuration this class exists but does nothing: `canCheck` is
/// false and `checkForUpdates()` is a no-op. The shipping app (built from
/// Diskwise.xcodeproj, which does depend on Sparkle) gets the real behavior.
///
/// Also does nothing when `Bundle.main.bundleIdentifier` is nil, which is the
/// case for the bare `DiskwiseDev` executable produced by `swift build`:
/// Sparkle expects a proper app bundle with an Info.plist (SUFeedURL,
/// SUPublicEDKey), and there is no update feed to check in that context.
@MainActor
final class Updater {
    static let shared = Updater()

    #if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController?
    #endif

    private init() {
        #if canImport(Sparkle)
        if Bundle.main.bundleIdentifier != nil {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
        #endif
    }

    /// Whether Sparkle periodically checks for updates in the background.
    var automaticallyChecks: Bool {
        get {
            #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates ?? false
            #else
            false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    /// Whether an update check can be started right now (false mid-check, or
    /// before Sparkle has finished starting up).
    var canCheck: Bool {
        #if canImport(Sparkle)
        controller?.updater.canCheckForUpdates ?? false
        #else
        false
        #endif
    }

    /// Shows Sparkle's "checking for updates" UI and, if one is found, its
    /// usual update prompt.
    func checkForUpdates() {
        #if canImport(Sparkle)
        controller?.checkForUpdates(nil)
        #endif
    }
}
