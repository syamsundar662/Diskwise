import CoreServices
import Foundation

public struct InstalledApp: Sendable, Hashable, Identifiable {
    public var path: String
    public var name: String
    public var bundleID: String
    public var version: String
    public var size: Int64?
    public var lastUsed: Date?

    public var id: String { path }
}

/// Files an app leaves behind in ~/Library.
public struct Leftover: Sendable, Hashable, Identifiable {
    public var path: String
    /// Which Library folder, e.g. "Caches".
    public var kind: String
    public var size: Int64?

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
}

public enum AppInventory {
    /// Third-party apps in /Applications (and one folder deep) and ~/Applications.
    public static func list(home: String = NSHomeDirectory(), fileManager: FileManager = .default) -> [InstalledApp] {
        var paths: [String] = []
        for base in ["/Applications", home + "/Applications"] {
            guard let names = try? fileManager.contentsOfDirectory(atPath: base) else { continue }
            for name in names {
                let path = base + "/" + name
                if name.hasSuffix(".app") {
                    paths.append(path)
                } else if !name.hasPrefix("."), let inner = try? fileManager.contentsOfDirectory(atPath: path) {
                    paths += inner.filter { $0.hasSuffix(".app") }.map { path + "/" + $0 }
                }
            }
        }
        return paths.compactMap { path in
            guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier, !id.hasPrefix("com.apple.") else { return nil }
            let info = bundle.infoDictionary ?? [:]
            let name = (fileManager.displayName(atPath: path) as NSString).deletingPathExtension
            return InstalledApp(path: path, name: name, bundleID: id,
                                version: info["CFBundleShortVersionString"] as? String ?? "",
                                lastUsed: lastUsed(path))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// When the app was last opened, from Spotlight.
    public static func lastUsed(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Support files, caches, preferences and containers that belong to the app,
    /// matched by bundle identifier (and by exact app name for a few folders).
    public static func leftovers(for app: InstalledApp, home: String = NSHomeDirectory(),
                                 fileManager: FileManager = .default) -> [Leftover] {
        let id = app.bundleID.lowercased()
        let bundleName = (Bundle(path: app.path)?.infoDictionary?["CFBundleName"] as? String)?.lowercased()
        let names = Set([app.name.lowercased(), bundleName].compactMap { $0 }.filter { $0.count >= 3 })

        func byID(_ entry: String) -> Bool {
            let e = entry.lowercased()
            return e == id || e.hasPrefix(id + ".")
        }
        func byName(_ entry: String) -> Bool { names.contains(entry.lowercased()) }

        let rules: [(folder: String, matches: (String) -> Bool)] = [
            ("Application Support", { byID($0) || byName($0) }),
            ("Caches", { byID($0) || byName($0) }),
            ("Preferences", byID),
            ("Saved Application State", byID),
            ("Containers", byID),
            ("Group Containers", { entry in let e = entry.lowercased(); return e == id || e.hasSuffix("." + id) }),
            ("Application Scripts", byID),
            ("HTTPStorages", byID),
            ("WebKit", byID),
            ("Cookies", byID),
            ("Logs", { byID($0) || byName($0) }),
            ("LaunchAgents", byID),
        ]
        var found: [Leftover] = []
        for rule in rules {
            let base = home + "/Library/" + rule.folder
            guard let entries = try? fileManager.contentsOfDirectory(atPath: base) else { continue }
            for entry in entries where rule.matches(entry) {
                found.append(Leftover(path: base + "/" + entry, kind: rule.folder))
            }
        }
        return found
    }
}

/// Things in Downloads you haven't opened in a while.
public struct OldDownload: Sendable, Hashable, Identifiable {
    public var path: String
    public var size: Int64
    public var added: Date?
    public var lastOpened: Date?
    public var isFolder: Bool

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
}

public enum Downloads {
    public static let oldDays = 90

    public static func old(home: String = NSHomeDirectory(), days: Int = oldDays, now: Date = Date(),
                           fileManager: FileManager = .default) -> [OldDownload] {
        let folder = URL(fileURLWithPath: home + "/Downloads")
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentAccessDateKey, .contentModificationDateKey,
                                      .isDirectoryKey, .isPackageKey, .totalFileAllocatedSizeKey]
        guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let added = v.addedToDirectoryDate ?? v.contentModificationDate
            let opened = v.contentAccessDate
            guard (added ?? .distantPast) < cutoff, (opened ?? .distantPast) < cutoff else { return nil }
            let folder = v.isDirectory == true
            let size = folder ? DiskUsage().size(of: url.path) : Int64(v.totalFileAllocatedSize ?? 0)
            return OldDownload(path: url.path, size: size, added: added, lastOpened: opened, isFolder: folder)
        }
        .sorted { $0.size > $1.size }
    }
}
