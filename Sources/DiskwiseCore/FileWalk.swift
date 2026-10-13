import Darwin
import Foundation

/// Thin wrapper over fts(3), the walker `du` uses: fast, no Foundation objects
/// per file, stays on one volume and never follows symlinks.
enum FileWalk {
    enum Decision { case go, skip, stop }

    static func walk(_ root: String, _ visit: (UnsafeMutablePointer<FTSENT>) -> Decision) {
        guard let cRoot = strdup(root) else { return }
        defer { free(cRoot) }
        var roots: [UnsafeMutablePointer<CChar>?] = [cRoot, nil]
        guard let fts = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
        defer { fts_close(fts) }
        while let ent = fts_read(fts) {
            switch visit(ent) {
            case .go: continue
            case .skip: fts_set(fts, ent, FTS_SKIP)
            case .stop: return
            }
        }
    }

    static func info(_ ent: UnsafeMutablePointer<FTSENT>) -> Int32 { Int32(ent.pointee.fts_info) }
    static func level(_ ent: UnsafeMutablePointer<FTSENT>) -> Int { Int(ent.pointee.fts_level) }
    static func path(_ ent: UnsafeMutablePointer<FTSENT>) -> String { String(cString: ent.pointee.fts_path) }

    static func name(_ ent: UnsafeMutablePointer<FTSENT>) -> String {
        let offset = MemoryLayout<FTSENT>.offset(of: \FTSENT.fts_name)!
        return String(cString: UnsafeRawPointer(ent).advanced(by: offset).assumingMemoryBound(to: CChar.self))
    }

    static func modified(_ ent: UnsafeMutablePointer<FTSENT>) -> Date {
        guard let st = ent.pointee.fts_statp else { return .distantPast }
        return Date(timeIntervalSince1970: TimeInterval(st.pointee.st_mtimespec.tv_sec))
    }
}

/// Size on disk like `du`: allocated blocks, every hard-linked file counted once.
/// One instance can be shared by several walks so overlapping trees don't double count.
public final class DiskUsage: @unchecked Sendable {
    private struct FileID: Hashable { let dev: Int32; let ino: UInt64 }
    private var seen = Set<FileID>()
    private let lock = NSLock()

    public init() {}

    /// Size of a file or a whole folder tree. Unreadable parts count as zero.
    public func size(of path: String, isCancelled: () -> Bool = { false }) -> Int64 {
        var total: Int64 = 0
        var visited = 0
        FileWalk.walk(path) { ent in
            visited += 1
            if visited % 4096 == 0, isCancelled() { return .stop }
            total += self.allocated(ent)
            return .go
        }
        return total
    }

    /// Bytes an entry adds, or 0 when it's a post-order visit, an error, or a
    /// hard link already counted.
    func allocated(_ ent: UnsafeMutablePointer<FTSENT>) -> Int64 {
        switch FileWalk.info(ent) {
        case FTS_D, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT: break
        default: return 0
        }
        guard let st = ent.pointee.fts_statp?.pointee else { return 0 }
        if st.st_nlink > 1, (st.st_mode & S_IFMT) == S_IFREG {
            let id = FileID(dev: st.st_dev, ino: st.st_ino)
            lock.lock()
            let fresh = seen.insert(id).inserted
            lock.unlock()
            if !fresh { return 0 }
        }
        return Int64(st.st_blocks) * 512
    }
}
