import Foundation

/// One removable thing in a cleanup group: a cache folder, a log, a simulator.
public struct CleanupItem: Sendable, Hashable, Identifiable {
    public var path: String
    public var name: String
    /// Where it comes from, e.g. "DerivedData" or "Code".
    public var source: String
    /// nil while still measuring.
    public var size: Int64?
    /// The open app that uses it; such items are skipped until the app quits.
    public var inUseBy: String?

    public var id: String { path }

    public init(path: String, name: String, source: String, size: Int64? = nil, inUseBy: String? = nil) {
        self.path = path
        self.name = name
        self.source = source
        self.size = size
        self.inUseBy = inUseBy
    }
}

public struct CleanupGroup: Sendable, Identifiable {
    public enum Removal: Sendable { case delete, trash, eraseSimulator, wipeEmulator }

    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let selectedByDefault: Bool
    public let removal: Removal
    let roots: [Root]
    let skipsOpenApps: Bool
    public var items: [CleanupItem] = []

    public var size: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }
    public var measuring: Bool { items.contains { $0.size == nil } }
}

/// A folder in a group: `children` makes each entry inside it its own item,
/// otherwise the folder is one item.
struct Root: Sendable {
    let path: String
    let children: Bool
    let label: String

    static func whole(_ path: String, _ label: String? = nil) -> Root {
        Root(path: path, children: false, label: label ?? (path as NSString).lastPathComponent)
    }

    static func each(_ path: String, _ label: String? = nil) -> Root {
        Root(path: path, children: true, label: label ?? (path as NSString).lastPathComponent)
    }
}

public struct RunningApp: Sendable, Hashable {
    public var name: String
    public var bundleID: String

    public init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

public enum CleanupCatalog {
    /// Electron apps keep their caches in Application Support.
    static let electronApps = ["Code", "Cursor", "Windsurf", "Antigravity", "Slack", "discord", "Claude",
                               "Microsoft Teams", "Notion", "Figma", "Comet", "Postman", "ChatGPT"]
    static let electronCaches = ["Cache", "Code Cache", "GPUCache", "CachedData", "CachedExtensionVSIXs",
                                 "CachedProfilesData", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
                                 "Service Worker/CacheStorage", "logs", "Crashpad/completed"]

    /// macOS's own caches in ~/Library/Caches: left alone.
    static let systemCaches: Set<String> = ["CloudKit", "GeoServices", "FamilyCircle", "familycircled", "PassKit",
                                            "Metadata", "SiriTTS", "TemporaryItems", "com.syam.Diskwise"]

    public static var groups: [CleanupGroup] {
        [
            CleanupGroup(id: "app-caches", title: "App caches",
                         detail: "Cache files apps rebuild on their own. Caches of open apps are skipped.",
                         symbol: "square.stack.3d.up.fill", selectedByDefault: true, removal: .delete,
                         roots: [.each("Library/Caches", "Caches")], skipsOpenApps: true),
            CleanupGroup(id: "app-support", title: "Electron app caches",
                         detail: "Caches of VS Code, Cursor, Slack, Discord and similar apps.",
                         symbol: "app.badge.fill", selectedByDefault: true, removal: .delete,
                         roots: electronApps.flatMap { app in
                             electronCaches.map { Root.whole("Library/Application Support/\(app)/\($0)", app) }
                         }, skipsOpenApps: true),
            CleanupGroup(id: "npm", title: "npm cache",
                         detail: "Downloaded packages. npm fetches them again when a project needs them.",
                         symbol: "shippingbox.fill", selectedByDefault: true, removal: .delete,
                         roots: [.whole(".npm/_cacache", "npm"), .whole(".npm/_npx", "npx"), .whole(".npm/_logs", "npm")],
                         skipsOpenApps: false),
            CleanupGroup(id: "js", title: "pnpm, Yarn and Bun",
                         detail: "Package stores. Installed projects keep working; new installs download again.",
                         symbol: "cube.box.fill", selectedByDefault: true, removal: .delete,
                         roots: [.whole("Library/pnpm/store", "pnpm"), .whole("Library/Caches/pnpm", "pnpm"),
                                 .whole("Library/Caches/Yarn", "Yarn"), .whole(".yarn/berry/cache", "Yarn"),
                                 .whole(".bun/install/cache", "Bun")],
                         skipsOpenApps: false),
            CleanupGroup(id: "gradle", title: "Gradle",
                         detail: "Dependencies, wrapper downloads and daemon logs. Rebuilt on the next build.",
                         symbol: "hammer.fill", selectedByDefault: true, removal: .delete,
                         roots: [.whole(".gradle/caches", "Gradle"), .whole(".gradle/wrapper/dists", "Gradle wrapper"),
                                 .whole(".gradle/daemon", "Gradle daemon")],
                         skipsOpenApps: false),
            CleanupGroup(id: "xcode", title: "Xcode build data",
                         detail: "DerivedData, previews and device support. Xcode recreates them as needed.",
                         symbol: "swift", selectedByDefault: true, removal: .delete,
                         roots: [.each("Library/Developer/Xcode/DerivedData", "DerivedData"),
                                 .each("Library/Developer/Xcode/iOS DeviceSupport", "iOS device support"),
                                 .each("Library/Developer/Xcode/watchOS DeviceSupport", "watchOS device support"),
                                 .each("Library/Developer/Xcode/macOS DeviceSupport", "macOS device support"),
                                 .whole("Library/Developer/Xcode/UserData/Previews", "SwiftUI previews"),
                                 .whole("Library/Developer/CoreSimulator/Caches", "Simulator caches"),
                                 .whole("Library/Caches/org.swift.swiftpm", "Swift packages"),
                                 .whole("Library/Caches/com.apple.dt.Xcode", "Xcode")],
                         skipsOpenApps: false),
            CleanupGroup(id: "python", title: "Python caches",
                         detail: "pip, uv and Poetry downloads. Fetched again when you install packages.",
                         symbol: "chevron.left.forwardslash.chevron.right", selectedByDefault: true, removal: .delete,
                         roots: [.whole(".cache/uv", "uv"), .whole(".cache/pip", "pip"), .whole("Library/Caches/pip", "pip"),
                                 .whole("Library/Caches/pypoetry", "Poetry"), .whole(".cache/pypoetry", "Poetry"),
                                 .whole(".conda/pkgs", "Conda")],
                         skipsOpenApps: false),
            CleanupGroup(id: "dev", title: "Other developer caches",
                         detail: "Homebrew, CocoaPods, test browsers, Rust, Go and JetBrains caches.",
                         symbol: "wrench.and.screwdriver.fill", selectedByDefault: true, removal: .delete,
                         roots: [.whole("Library/Caches/Homebrew", "Homebrew"), .whole("Library/Caches/CocoaPods", "CocoaPods"),
                                 .whole("Library/Caches/ms-playwright", "Playwright"), .whole(".cache/ms-playwright", "Playwright"),
                                 .whole(".cache/puppeteer", "Puppeteer"), .whole(".cache/chrome-devtools-mcp", "Chrome DevTools MCP"),
                                 .whole(".cache/selenium", "Selenium"), .whole("Library/Caches/go-build", "Go"),
                                 .whole("Library/Caches/cargo-xwin", "cargo-xwin"), .whole(".cargo/registry/cache", "Cargo"),
                                 .whole(".cargo/registry/src", "Cargo"), .whole(".cache/prisma", "Prisma"),
                                 .whole("Library/Caches/node-gyp", "node-gyp"), .whole("Library/Caches/deno", "Deno"),
                                 .whole("Library/Caches/typescript", "TypeScript"), .whole("Library/Caches/JetBrains", "JetBrains")],
                         skipsOpenApps: true),
            CleanupGroup(id: "logs", title: "Logs and crash reports",
                         detail: "Old app logs and diagnostic reports.",
                         symbol: "doc.text.fill", selectedByDefault: true, removal: .delete,
                         roots: [.each("Library/Logs", "Logs")], skipsOpenApps: false),
            CleanupGroup(id: "simulators", title: "iOS Simulator data",
                         detail: "Apps and data inside simulators. Erasing resets them but keeps the simulators.",
                         symbol: "iphone", selectedByDefault: false, removal: .eraseSimulator,
                         roots: [.each("Library/Developer/CoreSimulator/Devices", "Simulator")], skipsOpenApps: false),
            CleanupGroup(id: "emulators", title: "Android emulator data",
                         detail: "Apps, data and snapshots inside emulators. Like Wipe Data: the emulators stay.",
                         symbol: "candybarphone", selectedByDefault: false, removal: .wipeEmulator,
                         roots: [.each(".android/avd", "Emulator")], skipsOpenApps: false),
            CleanupGroup(id: "android-sdk", title: "Android SDK downloads",
                         detail: "NDK versions and emulator system images. The SDK Manager downloads them again.",
                         symbol: "shippingbox.circle.fill", selectedByDefault: false, removal: .delete,
                         roots: [.each("Library/Android/sdk/ndk", "NDK"), .each("Library/Android/sdk/system-images", "System image")],
                         skipsOpenApps: false),
            CleanupGroup(id: "models", title: "Downloaded AI models",
                         detail: "Hugging Face and Ollama models. Big to download again, so not selected.",
                         symbol: "brain.fill", selectedByDefault: false, removal: .delete,
                         roots: [.each(".cache/huggingface/hub", "Hugging Face"), .whole(".cache/huggingface/xet", "Hugging Face"),
                                 .whole(".ollama/models", "Ollama"), .whole(".lmstudio/models", "LM Studio"),
                                 .whole(".cache/whisper", "Whisper"), .whole(".cache/torch", "PyTorch")],
                         skipsOpenApps: false),
            CleanupGroup(id: "dotcache", title: "Other caches in ~/.cache",
                         detail: "Caches of command line tools. Check what you still need.",
                         symbol: "folder.fill", selectedByDefault: false, removal: .delete,
                         roots: [.each(".cache", "~/.cache")], skipsOpenApps: false),
            CleanupGroup(id: "archives", title: "Xcode archives",
                         detail: "Builds you archived for release. Keep them if you need their crash symbols.",
                         symbol: "archivebox.fill", selectedByDefault: false, removal: .trash,
                         roots: [.each("Library/Developer/Xcode/Archives", "Archives")], skipsOpenApps: false),
            CleanupGroup(id: "backups", title: "iPhone and iPad backups",
                         detail: "Local device backups. Moved to the Trash.",
                         symbol: "iphone.gen3", selectedByDefault: false, removal: .trash,
                         roots: [.each("Library/Application Support/MobileSync/Backup", "Backup")], skipsOpenApps: false),
        ]
    }

    /// Every group with its items listed (sizes still nil). Only reads folder
    /// listings, so it's quick; measure items afterwards.
    public static func list(home: String = NSHomeDirectory(), running: [RunningApp] = [],
                            fileManager: FileManager = .default) -> [CleanupGroup] {
        let all = groups
        let claimed = Set(all.flatMap { $0.roots.map(\.path) })
        return all.compactMap { group in
            var group = group
            var seen = Set<String>()
            for root in group.roots {
                let base = home + "/" + root.path
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: base, isDirectory: &isDir) else { continue }
                if root.children {
                    guard isDir.boolValue, let names = try? fileManager.contentsOfDirectory(atPath: base) else { continue }
                    for name in names.sorted() where !skip(name, in: root.path, claimed: claimed) {
                        let path = base + "/" + name
                        guard seen.insert(path).inserted else { continue }
                        group.items.append(CleanupItem(path: path, name: displayName(name, path: path, group: group.id),
                                                       source: root.label,
                                                       inUseBy: group.skipsOpenApps ? owner(of: name, running: running) : nil))
                    }
                } else if seen.insert(base).inserted {
                    let owner = group.skipsOpenApps ? owner(of: root.label, running: running) : nil
                    let name = group.id == "app-support" ? (root.path as NSString).lastPathComponent : root.label
                    group.items.append(CleanupItem(path: base, name: name, source: root.label, inUseBy: owner))
                }
            }
            if group.id == "simulators" {
                for i in group.items.indices where simulatorBooted(group.items[i].path) { group.items[i].inUseBy = "Simulator" }
            }
            if group.id == "emulators" {
                group.items.removeAll { !$0.path.hasSuffix(".avd") }
                let running = runningEmulators()
                for i in group.items.indices {
                    let avd = ((group.items[i].path as NSString).lastPathComponent as NSString).deletingPathExtension
                    if running.contains(avd) { group.items[i].inUseBy = "Android Emulator" }
                }
            }
            return group.items.isEmpty ? nil : group
        }
    }

    /// Size on disk of one item.
    public static func measure(_ item: CleanupItem) -> Int64 {
        DiskUsage().size(of: item.path)
    }

    static func skip(_ name: String, in root: String, claimed: Set<String>) -> Bool {
        if name.hasPrefix(".") { return true }
        if root == "Library/Caches", name.hasPrefix("com.apple.") || systemCaches.contains(name) { return true }
        if root == "Library/Developer/CoreSimulator/Devices", name.hasSuffix(".plist") || name == ".default_created" {
            return true
        }
        // Claimed by a more specific group (Library/Caches/Homebrew is "Other developer caches").
        let path = root + "/" + name
        return claimed.contains { $0 == path || $0.hasPrefix(path + "/") }
    }

    /// The open app an item belongs to: "com.google.Chrome" or "Google" for Chrome,
    /// "com.todesktop.x.ShipIt" for that app's updater.
    public static func owner(of name: String, running: [RunningApp]) -> String? {
        let lower = name.lowercased()
        for app in running where !app.bundleID.hasPrefix("com.apple.") {
            let id = app.bundleID.lowercased()
            if lower == id || lower.hasPrefix(id + ".") || lower == app.name.lowercased() { return app.name }
            let parts = id.split(separator: ".")
            if !lower.contains("."), parts.count >= 3, lower == parts[1] { return app.name }
        }
        return nil
    }

    static func displayName(_ name: String, path: String, group: String) -> String {
        switch group {
        case "simulators":
            guard let plist = NSDictionary(contentsOfFile: path + "/device.plist") else { return name }
            let device = plist["name"] as? String ?? name
            let runtime = (plist["runtime"] as? String)?
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
            guard let runtime else { return device }
            // "iOS 17 5" -> "iOS 17.5"
            let parts = runtime.split(separator: " ")
            let os = parts.first.map(String.init) ?? ""
            return "\(device) (\(os) \(parts.dropFirst().joined(separator: ".")))"
        case "emulators":
            return (name as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
        case "backups":
            let info = NSDictionary(contentsOfFile: path + "/Info.plist")
            return info?["Device Name"] as? String ?? name
        case "models":
            // "models--meta-llama--Llama-3" -> "meta-llama/Llama-3"
            guard name.hasPrefix("models--") else { return name }
            return name.dropFirst(8).replacingOccurrences(of: "--", with: "/")
        default:
            return name
        }
    }

    /// Names of emulators running now, from their "-avd <name>" argument
    /// (lock files in the .avd folder outlive the emulator, so they can't tell).
    static func runningEmulators() -> Set<String> {
        let output = Shell.run("/usr/bin/pgrep", ["-fl", "qemu-system"]).output
        var names = Set<String>()
        for line in output.split(separator: "\n") {
            let words = line.split(separator: " ")
            if let i = words.firstIndex(of: "-avd"), i + 1 < words.count { names.insert(String(words[i + 1])) }
        }
        return names
    }

    /// The data "Wipe Data" resets: the user data image, cache and snapshots.
    static func isEmulatorData(_ name: String) -> Bool {
        name == "snapshots" || name.hasPrefix("userdata-qemu.img") || name.hasPrefix("cache.img")
    }

    static func simulatorBooted(_ path: String) -> Bool {
        (NSDictionary(contentsOfFile: path + "/device.plist")?["state"] as? Int) == 3
    }
}

public struct RemovalReport: Sendable {
    public var freed: Int64 = 0
    public var removed: [String] = []
    /// Path to a short reason.
    public var failed: [String: String] = [:]

    public init() {}
}

public enum Remover {
    /// Removes cleanup items the way their group says: deleted (caches), to the
    /// Trash (archives, backups) or erased through simctl (simulators).
    public static func remove(_ items: [CleanupItem], removal: CleanupGroup.Removal,
                              home: String = NSHomeDirectory(), fileManager: FileManager = .default) -> RemovalReport {
        var report = RemovalReport()
        for item in items where item.inUseBy == nil {
            do {
                switch removal {
                case .delete: try SafeDelete.remove(item.path, mode: .delete, home: home, fileManager: fileManager)
                case .trash: try SafeDelete.remove(item.path, mode: .trash, home: home, fileManager: fileManager)
                case .wipeEmulator:
                    for entry in (try? fileManager.contentsOfDirectory(atPath: item.path)) ?? []
                    where CleanupCatalog.isEmulatorData(entry) {
                        try SafeDelete.remove(item.path + "/" + entry, mode: .delete, home: home, fileManager: fileManager)
                    }
                case .eraseSimulator:
                    let udid = (item.path as NSString).lastPathComponent
                    let result = Shell.run("/usr/bin/xcrun", ["simctl", "erase", udid])
                    if result.status != 0 { throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: result.output]) }
                }
                report.removed.append(item.path)
                if removal == .wipeEmulator, let before = item.size {
                    report.freed += max(before - DiskUsage().size(of: item.path), 0)
                } else {
                    report.freed += item.size ?? 0
                }
            } catch {
                // Count what did go away from a partly removed folder.
                if removal == .delete, let before = item.size {
                    let left = fileManager.fileExists(atPath: item.path) ? DiskUsage().size(of: item.path) : 0
                    report.freed += max(before - left, 0)
                }
                report.failed[item.path] = error.localizedDescription
            }
        }
        return report
    }
}
