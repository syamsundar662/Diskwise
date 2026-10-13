import Foundation

/// The single gate every removal goes through. Anything outside the home
/// folder, a top-level folder itself, or private data (keychains, mail, cloud
/// drives) is refused, whatever the caller asks for.
public enum SafeDelete {
    public enum Mode: Sendable { case delete, trash }

    /// Folders that may be emptied but never removed themselves.
    static let protectedFolders: Set<String> = [
        "", "Library", "Library/Caches", "Library/Application Support", "Library/Preferences",
        "Library/Containers", "Library/Group Containers", "Library/Developer", "Library/Developer/Xcode",
        "Library/Developer/CoreSimulator", "Library/Developer/CoreSimulator/Devices", "Library/Logs",
        "Library/LaunchAgents", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Public",
        "Applications", ".cache", ".npm", ".gradle", ".config", ".local", ".cargo", ".Trash",
    ]

    /// Never touched at all, inside or out.
    static let privateFolders = [
        "Library/Keychains", ".ssh", ".gnupg", "Library/Mail", "Library/Messages", "Library/Mobile Documents",
        "Library/CloudStorage", "Library/Accounts", "Library/Calendars", "Library/Application Support/AddressBook",
        "Library/Photos", ".claude", ".aws",
    ]

    /// nil when `path` may be removed, otherwise the reason it may not.
    public static func refusal(for path: String, home: String = NSHomeDirectory()) -> String? {
        guard path.hasPrefix("/") else { return "not an absolute path" }
        let standard = (path as NSString).standardizingPath
        let name = (standard as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { return "not a file" }
        // Resolve links in the parent folders (not the item: removing a link removes only the link).
        let parent = ((standard as NSString).deletingLastPathComponent as NSString).resolvingSymlinksInPath
        let full = parent + "/" + name
        let root = (home as NSString).resolvingSymlinksInPath
        guard full.hasPrefix(root + "/") else { return "outside your home folder" }
        let relative = String(full.dropFirst(root.count + 1))
        if protectedFolders.contains(relative) { return "a protected folder" }
        if privateFolders.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { return "private data" }
        return nil
    }

    /// Apps may be moved to the Trash from /Applications too, except Apple's own.
    public static func appRefusal(for path: String, home: String = NSHomeDirectory()) -> String? {
        let standard = (path as NSString).standardizingPath
        guard standard.hasSuffix(".app") else { return "not an app" }
        let inApplications = standard.hasPrefix("/Applications/") || standard.hasPrefix(home + "/Applications/")
        guard inApplications else { return "not in an Applications folder" }
        if let id = Bundle(path: standard)?.bundleIdentifier, id.hasPrefix("com.apple.") { return "part of macOS" }
        return nil
    }

    /// Removes one item, permanently or to the Trash. When a permanent delete
    /// trips over a few locked files, everything else in the folder is still removed.
    public static func remove(_ path: String, mode: Mode, home: String = NSHomeDirectory(),
                              fileManager: FileManager = .default) throws {
        if let reason = refusal(for: path, home: home) {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "Refused: \(reason)"])
        }
        switch mode {
        case .trash:
            try Trash.move(path, fileManager: fileManager)
        case .delete:
            do {
                try fileManager.removeItem(atPath: path)
            } catch {
                guard let children = try? fileManager.contentsOfDirectory(atPath: path) else { throw error }
                var lastError: Error?
                for child in children {
                    do { try fileManager.removeItem(atPath: path + "/" + child) } catch { lastError = error }
                }
                try? fileManager.removeItem(atPath: path)
                if let lastError, fileManager.fileExists(atPath: path) { throw lastError }
            }
        }
    }
}

public enum Trash {
    /// Moves to the Trash; items owned by root (like some apps) go through
    /// Finder, which asks for the admin password.
    public static func move(_ path: String, fileManager: FileManager = .default) throws {
        do {
            try fileManager.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        } catch {
            let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let result = Shell.run("/usr/bin/osascript",
                                   ["-e", "tell application \"Finder\" to delete (POSIX file \"\(escaped)\")"])
            if result.status != 0 || fileManager.fileExists(atPath: path) { throw error }
        }
    }

    /// Empties the Trash through Finder (reading ~/.Trash needs Full Disk Access).
    @discardableResult
    public static func empty() -> Bool {
        Shell.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"]).status == 0
    }

    /// Size of the Trash, or nil when macOS won't let us look inside.
    public static func size(home: String = NSHomeDirectory()) -> Int64? {
        let path = home + "/.Trash"
        guard (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil else { return nil }
        return DiskUsage().size(of: path)
    }
}

enum Shell {
    struct Result { let status: Int32; let output: String }

    static func run(_ tool: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return Result(status: -1, output: "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
