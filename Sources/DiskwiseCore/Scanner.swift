import Darwin
import Foundation

/// A folder (or big file) in the scanned tree. Only children worth showing are
/// kept; the rest are folded into `restSize`/`restCount`.
public struct FolderNode: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var size: Int64
    public var isDirectory: Bool
    public var children: [FolderNode]
    public var restSize: Int64
    public var restCount: Int

    public var id: String { name }

    public init(name: String, size: Int64, isDirectory: Bool, children: [FolderNode] = [],
                restSize: Int64 = 0, restCount: Int = 0) {
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
        self.restSize = restSize
        self.restCount = restCount
    }

    public func child(named name: String) -> FolderNode? { children.first { $0.name == name } }

    /// The node at a path relative to this one ("Library/Caches"), if it was kept.
    public func node(at relative: String) -> FolderNode? {
        var node = self
        for part in relative.split(separator: "/") {
            guard let next = node.child(named: String(part)) else { return nil }
            node = next
        }
        return node
    }

    /// Removes the node at `relative` (after it was deleted) and shrinks every parent.
    public mutating func remove(at relative: [String]) -> Int64 {
        guard let first = relative.first, let i = children.firstIndex(where: { $0.name == first }) else { return 0 }
        let freed: Int64
        if relative.count == 1 {
            freed = children[i].size
            children.remove(at: i)
        } else {
            freed = children[i].remove(at: Array(relative.dropFirst()))
            children.sort { $0.size > $1.size }
        }
        size -= freed
        return freed
    }
}

public struct LargeFile: Codable, Sendable, Hashable, Identifiable {
    public var path: String
    public var size: Int64
    public var modified: Date
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, size: Int64, modified: Date) {
        self.path = path
        self.size = size
        self.modified = modified
    }
}

/// A folder named like build output or dependencies (node_modules, build, Pods...).
public struct JunkFolder: Codable, Sendable, Hashable {
    public var path: String
    public var size: Int64

    public init(path: String, size: Int64) {
        self.path = path
        self.size = size
    }
}

public struct ScanResult: Codable, Sendable {
    public var home: String
    public var root: FolderNode
    public var largeFiles: [LargeFile]
    public var junk: [JunkFolder]
    public var date: Date
    public var seconds: Double
    /// Folders we were not allowed to read.
    public var unreadable: Int
}

public struct ScanProgress: Sendable {
    public var bytes: Int64
    public var items: Int
    /// Top-level folder being scanned now.
    public var current: String
}

/// Walks the home folder once and builds what every view needs: the folder
/// tree for exploring, big files, and dependency/build folders in projects.
public enum Scanner {
    public struct Options: Sendable {
        /// Children smaller than this are folded into "smaller items".
        public var keepSize: Int64 = 20 * Bytes.mb
        public var maxChildren = 60
        public var largeFileSize: Int64 = 100 * Bytes.mb
        /// Home-relative paths never entered: cloud folders (listing them can
        /// download), Trash, and other apps' private data unless we have Full Disk Access.
        public var excluded: Set<String> = ["Library/CloudStorage", "Library/Mobile Documents", ".Trash"]

        public init() {}

        public static func standard(fullDiskAccess: Bool) -> Options {
            var o = Options()
            if !fullDiskAccess {
                // Reading these asks for permission (app data, Apple Music, Photos) one prompt at a time.
                o.excluded.formUnion(["Library/Containers", "Library/Group Containers", "Library/Mail",
                                      "Library/Messages", "Library/Safari", "Library/Application Support/MobileSync",
                                      "Music/Music", "Music/iTunes", "Pictures/Photos Library.photoslibrary",
                                      "Pictures/Photo Booth Library"])
            }
            return o
        }
    }

    private final class Frame {
        let ent: UnsafeMutablePointer<FTSENT>
        let name: String
        var size: Int64 = 0
        var kept: [FolderNode] = []
        var restSize: Int64 = 0
        var restCount = 0
        var junk = false

        init(ent: UnsafeMutablePointer<FTSENT>, name: String) {
            self.ent = ent
            self.name = name
        }
    }

    public static func scan(home: String, options: Options = Options(),
                            progress: (ScanProgress) -> Void = { _ in },
                            isCancelled: () -> Bool = { false }) -> ScanResult? {
        let started = Date()
        let usage = DiskUsage()
        var stack: [Frame] = []
        var root: FolderNode?
        var large: [LargeFile] = []
        var junk: [JunkFolder] = []
        var insideJunk = false
        var unreadable = 0
        var bytes: Int64 = 0
        var items = 0
        var lastReport = Date()
        var cancelled = false
        let homePrefix = home.hasSuffix("/") ? home : home + "/"

        func relative(_ path: String) -> String {
            path.hasPrefix(homePrefix) ? String(path.dropFirst(homePrefix.count)) : ""
        }

        func add(_ node: FolderNode, to parent: Frame) {
            parent.size += node.size
            if node.size >= options.keepSize {
                parent.kept.append(node)
            } else {
                parent.restSize += node.size
                parent.restCount += 1
            }
        }

        FileWalk.walk(home) { ent in
            items += 1
            if items % 2048 == 0 {
                if isCancelled() { cancelled = true; return .stop }
                if Date().timeIntervalSince(lastReport) > 0.25 {
                    lastReport = Date()
                    progress(ScanProgress(bytes: bytes, items: items, current: stack.count > 1 ? stack[1].name : ""))
                }
            }
            let info = FileWalk.info(ent)
            let level = FileWalk.level(ent)
            switch info {
            case FTS_D:
                let name = FileWalk.name(ent)
                if level > 0, level <= 4, !options.excluded.isEmpty {
                    let rel = relative(FileWalk.path(ent))
                    if options.excluded.contains(rel) { return .skip }
                }
                let frame = Frame(ent: ent, name: level == 0 ? home : name)
                let own = usage.allocated(ent)
                frame.size += own
                bytes += own
                if !insideJunk, ProjectJunk.names.contains(name), ProjectJunk.eligible(relative(FileWalk.path(ent))) {
                    frame.junk = true
                    insideJunk = true
                }
                stack.append(frame)

            case FTS_DP, FTS_DNR, FTS_ERR:
                if info != FTS_DP { unreadable += 1 }
                guard let frame = stack.last, frame.ent == ent else { return .go }
                stack.removeLast()
                var kept = frame.kept.sorted { $0.size > $1.size }
                var restSize = frame.restSize, restCount = frame.restCount
                if kept.count > options.maxChildren {
                    for extra in kept[options.maxChildren...] { restSize += extra.size; restCount += 1 }
                    kept.removeSubrange(options.maxChildren...)
                }
                let node = FolderNode(name: frame.name, size: frame.size, isDirectory: true, children: kept,
                                      restSize: restSize, restCount: restCount)
                if frame.junk {
                    junk.append(JunkFolder(path: FileWalk.path(ent), size: frame.size))
                    insideJunk = false
                }
                if let parent = stack.last { add(node, to: parent) } else { root = node }

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let parent = stack.last else { return .go }
                let size = usage.allocated(ent)
                bytes += size
                if size >= options.keepSize {
                    add(FolderNode(name: FileWalk.name(ent), size: size, isDirectory: false), to: parent)
                    if info == FTS_F, size >= options.largeFileSize, !insideJunk {
                        let path = FileWalk.path(ent)
                        if userVisible(relative(path)) {
                            large.append(LargeFile(path: path, size: size, modified: FileWalk.modified(ent)))
                        }
                    }
                } else {
                    parent.size += size
                    parent.restSize += size
                    parent.restCount += 1
                }

            default:
                break
            }
            return .go
        }
        guard !cancelled, let root else { return nil }
        return ScanResult(home: home, root: root, largeFiles: large.sorted { $0.size > $1.size }, junk: junk,
                          date: Date(), seconds: Date().timeIntervalSince(started), unreadable: unreadable)
    }

    /// Files the user put there themselves: not in ~/Library, hidden folders or app bundles.
    static func userVisible(_ relative: String) -> Bool {
        let parts = relative.split(separator: "/")
        guard let first = parts.first, !first.hasPrefix("."), first != "Library", first != "Applications" else { return false }
        return !parts.dropLast().contains { $0.hasSuffix(".app") || $0.hasPrefix(".") }
    }
}
