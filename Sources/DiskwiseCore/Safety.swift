import Foundation

/// How safe it is to remove something, with a short reason shown next to it.
public enum Safety: String, Sendable, Comparable {
    /// Rebuilt automatically: caches, logs, build output.
    case safe
    /// Your own files, or data that is slow to get back. Check before removing.
    case review
    /// App data, settings, keys or protected folders. Diskwise won't offer to remove it.
    case unsafe

    public var title: String {
        switch self {
        case .safe: return "Safe to delete"
        case .review: return "Review first"
        case .unsafe: return "Not safe to delete"
        }
    }

    public static func < (a: Safety, b: Safety) -> Bool {
        let order: [Safety] = [.safe, .review, .unsafe]
        return order.firstIndex(of: a)! < order.firstIndex(of: b)!
    }
}

public struct SafetyVerdict: Sendable, Equatable {
    public var safety: Safety
    public var reason: String

    public init(_ safety: Safety, _ reason: String) {
        self.safety = safety
        self.reason = reason
    }
}

public enum SafetyAdvisor {
    /// Verdicts for the cleanup groups.
    public static func verdict(forGroup id: String) -> SafetyVerdict {
        switch id {
        case "app-caches", "app-support", "npm", "js", "gradle", "xcode", "python", "dev":
            return SafetyVerdict(.safe, "Rebuilt automatically when an app or tool needs it")
        case "logs":
            return SafetyVerdict(.safe, "Old logs and crash reports nothing depends on")
        case "simulators":
            return SafetyVerdict(.review, "Resets the apps and data inside your simulators")
        case "emulators":
            return SafetyVerdict(.review, "Resets the apps and data inside your emulators")
        case "android-sdk", "models":
            return SafetyVerdict(.review, "Safe, but large to download again")
        case "dotcache":
            return SafetyVerdict(.review, "Tool caches; check what each one holds")
        case "archives":
            return SafetyVerdict(.review, "Needed to read crash reports of released builds")
        case "backups":
            return SafetyVerdict(.review, "Your only copy of these device backups may be here")
        default:
            return SafetyVerdict(.review, "Check what this is before removing it")
        }
    }

    /// Verdict for a leftover of an app being uninstalled, by its Library folder.
    public static func verdict(forLeftoverKind kind: String) -> SafetyVerdict {
        switch kind {
        case "Caches", "Logs", "HTTPStorages", "WebKit", "Saved Application State", "Cookies":
            return SafetyVerdict(.safe, "Cache or state of the app you are removing")
        default:
            return SafetyVerdict(.review, "Settings and data of the app you are removing; goes to the Trash")
        }
    }

    /// Cleanup roots, home relative, with their group's verdict.
    private static let roots: [(path: String, verdict: SafetyVerdict)] = CleanupCatalog.groups.flatMap { group in
        group.roots.map { (path: $0.path, verdict: verdict(forGroup: group.id)) }
    }

    /// Where apps keep data and settings: never offered for removal.
    private static let appData = ["Library/Application Support", "Library/Containers", "Library/Group Containers",
                                  "Library/Preferences", "Library/LaunchAgents", "Library/Application Scripts",
                                  "Library/Keychains", "Library/Cookies", "Library/Saved Application State"]
    /// Hidden folders that hold settings or keys.
    private static let configs: Set<String> = [".ssh", ".gnupg", ".aws", ".config", ".kube", ".docker", ".claude",
                                               ".codex", ".gitconfig", ".zshrc", ".zprofile", ".bashrc", ".bash_profile",
                                               ".netrc", ".npmrc", ".local", ".vscode", ".cursor"]
    private static let userFolders: Set<String> = ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Public"]

    /// Verdict for any file or folder in the home folder (Space Lens, Explore, file lists).
    public static func verdict(for path: String, home: String = NSHomeDirectory()) -> SafetyVerdict {
        let standard = (path as NSString).standardizingPath
        if SafeDelete.isExcluded(standard) { return SafetyVerdict(.unsafe, "You told Diskwise never to touch this folder") }
        let prefix = home.hasSuffix("/") ? home : home + "/"
        guard standard.hasPrefix(prefix) else { return SafetyVerdict(.unsafe, "Outside your home folder") }
        let relative = String(standard.dropFirst(prefix.count))
        let parts = relative.split(separator: "/").map(String.init)

        // Inside a cleanup root (a cache, a log folder...): the group's verdict.
        for root in roots where relative == root.path || relative.hasPrefix(root.path + "/") {
            return root.verdict
        }
        // Folders that only hold package caches: Cleanup empties them from the inside.
        if relative == ".npm" || relative == ".gradle" {
            return SafetyVerdict(.safe, "Package caches. Cleanup removes them and they download again when needed")
        }
        if let reason = SafeDelete.refusal(for: standard, home: home) {
            switch reason {
            case "private data": return SafetyVerdict(.unsafe, "Private data such as keys, mail or cloud files")
            case "a protected folder": return SafetyVerdict(.unsafe, "An important folder; clean what is inside it instead")
            default: return SafetyVerdict(.unsafe, "Diskwise never removes this")
            }
        }
        // Project build output and dependencies, or anything inside them.
        for (i, part) in parts.enumerated() where ProjectJunk.names.contains(part) {
            let junkPath = prefix + parts[...i].joined(separator: "/")
            if !ProjectJunk.items(from: [JunkFolder(path: junkPath, size: 0)]).isEmpty {
                return SafetyVerdict(.safe, "Build output or dependencies your tools recreate")
            }
        }
        if parts.contains(".git") { return SafetyVerdict(.unsafe, "The history of a project") }
        if appData.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) {
            return SafetyVerdict(.unsafe, "Apps keep their data and settings here")
        }
        if let first = parts.first {
            if configs.contains(first) { return SafetyVerdict(.unsafe, "Settings or keys for your tools") }
            if parts.contains(where: { $0.hasSuffix(".app") }) {
                return SafetyVerdict(.review, "An app. Use the Uninstaller to remove it with its files")
            }
            if userFolders.contains(first) || !first.hasPrefix(".") && first != "Library" {
                return SafetyVerdict(.review, "Your files. They go to the Trash, so you can put them back")
            }
            if first.hasPrefix(".") { return SafetyVerdict(.review, "Data of a command line tool; check what it is") }
        }
        return SafetyVerdict(.review, "Check what this is before removing it")
    }
}

extension CleanupGroup {
    public var verdict: SafetyVerdict { SafetyAdvisor.verdict(forGroup: id) }
}
