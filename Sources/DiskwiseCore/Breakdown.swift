import Foundation

public enum StorageCategory: String, CaseIterable, Sendable {
    case cleanable = "Cleanable"
    case apps = "Apps"
    case documents = "Documents"
    case projects = "Projects & dev"
    case library = "App data"
    case system = "System & other"
}

/// Splits used space into categories that don't overlap: cleanable space is
/// taken out of the category its folder sits in, and whatever the scan
/// couldn't see (macOS, other users, purgeable space) is "System & other".
public enum Breakdown {
    static let documentFolders: Set<String> = ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music"]

    public static func compute(disk: DiskInfo, home: FolderNode?, homePath: String = NSHomeDirectory(),
                               apps: Int64, cleanable: [(path: String, size: Int64)]) -> [(StorageCategory, Int64)] {
        var sizes: [StorageCategory: Int64] = [:]
        sizes[.apps] = apps
        let cleanTotal = cleanable.reduce(0) { $0 + $1.size }
        sizes[.cleanable] = cleanTotal
        if let home {
            let documents = home.children.filter { documentFolders.contains($0.name) }.reduce(0) { $0 + $1.size }
            let library = home.child(named: "Library")?.size ?? 0
            sizes[.documents] = documents
            sizes[.library] = library
            sizes[.projects] = max(home.size - documents - library, 0)
            for item in cleanable {
                let category = category(of: item.path, homePath: homePath)
                sizes[category] = max((sizes[category] ?? 0) - item.size, 0)
            }
        }
        let known = sizes.values.reduce(0, +)
        sizes[.system] = max(disk.used - known, 0)
        return StorageCategory.allCases.compactMap { c in sizes[c].map { (c, $0) } }
    }

    static func category(of path: String, homePath: String) -> StorageCategory {
        let prefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        guard path.hasPrefix(prefix) else { return .system }
        let first = path.dropFirst(prefix.count).split(separator: "/").first.map(String.init) ?? ""
        if first == "Library" { return .library }
        if documentFolders.contains(first) { return .documents }
        return .projects
    }
}
