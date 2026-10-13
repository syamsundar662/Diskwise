import Foundation

/// Dependency and build folders inside projects. They are rebuilt by the
/// project's own tools (npm install, gradle, pod install...), so removing them
/// from projects you aren't working on is safe.
public struct ProjectJunkItem: Sendable, Hashable, Identifiable {
    public var path: String
    public var size: Int64
    /// What recreates it, e.g. "npm install".
    public var kind: String
    /// The project folder that owns it.
    public var project: String
    public var lastTouched: Date?

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    /// The project folder's name, with its parent's when the folder name is
    /// generic: "swastricare-mobile-swift › app" instead of "app".
    public var projectName: String {
        let name = (project as NSString).lastPathComponent
        guard ProjectJunk.genericNames.contains(name.lowercased()) else { return name }
        var parent = (project as NSString).deletingLastPathComponent
        while ProjectJunk.genericNames.contains((parent as NSString).lastPathComponent.lowercased()) {
            parent = (parent as NSString).deletingLastPathComponent
        }
        return "\((parent as NSString).lastPathComponent) › \(name)"
    }

    public func isStale(days: Int = ProjectJunk.staleDays, now: Date = Date()) -> Bool {
        guard let lastTouched else { return true }
        return now.timeIntervalSince(lastTouched) > Double(days) * 86_400
    }
}

public enum ProjectJunk {
    public static let staleDays = 30
    static let genericNames: Set<String> = ["app", "android", "ios", "web", "mobile", "frontend", "backend", "client",
                                            "server", "api", "src", "desktop", "apps", "packages", "admin"]

    struct Rule {
        let name: String
        /// The folder only counts when one of these sits next to it.
        let markers: [String]
        let kind: String
    }

    static let rules: [Rule] = [
        Rule(name: "node_modules", markers: ["package.json"], kind: "npm install"),
        Rule(name: ".next", markers: ["package.json"], kind: "Next.js build"),
        Rule(name: ".nuxt", markers: ["package.json"], kind: "Nuxt build"),
        Rule(name: ".svelte-kit", markers: ["package.json"], kind: "SvelteKit build"),
        Rule(name: ".turbo", markers: ["package.json", "turbo.json"], kind: "Turborepo cache"),
        Rule(name: ".parcel-cache", markers: ["package.json"], kind: "Parcel cache"),
        Rule(name: ".angular", markers: ["angular.json"], kind: "Angular cache"),
        Rule(name: ".expo", markers: ["package.json"], kind: "Expo cache"),
        Rule(name: "Pods", markers: ["Podfile"], kind: "pod install"),
        Rule(name: "target", markers: ["Cargo.toml", "pom.xml"], kind: "Rust/Maven build"),
        Rule(name: "build", markers: ["build.gradle", "build.gradle.kts", "pubspec.yaml"], kind: "Gradle/Flutter build"),
        Rule(name: ".gradle", markers: ["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"],
             kind: "Gradle project cache"),
        Rule(name: ".dart_tool", markers: ["pubspec.yaml"], kind: "Dart tool cache"),
        Rule(name: ".build", markers: ["Package.swift"], kind: "Swift build"),
        Rule(name: ".venv", markers: ["pyproject.toml", "requirements.txt", "setup.py"], kind: "Python venv"),
        Rule(name: "venv", markers: ["pyproject.toml", "requirements.txt", "setup.py"], kind: "Python venv"),
    ]

    public static let names: Set<String> = Set(rules.map(\.name))

    /// Only real projects: not inside ~/Library, hidden top-level folders
    /// (~/.vscode extensions, ~/.nvm globals...) or app bundles.
    public static func eligible(_ relative: String) -> Bool {
        let parts = relative.split(separator: "/")
        guard parts.count >= 2, let first = parts.first,
              !first.hasPrefix("."), first != "Library", first != "Applications" else { return false }
        return !parts.contains { $0.hasSuffix(".app") }
    }

    /// Keeps the scanned folders whose project marker exists, with their
    /// project's last activity.
    public static func items(from folders: [JunkFolder], fileManager: FileManager = .default) -> [ProjectJunkItem] {
        folders.compactMap { folder in
            let name = (folder.path as NSString).lastPathComponent
            let project = (folder.path as NSString).deletingLastPathComponent
            guard let rule = rules.first(where: { rule in
                rule.name == name && rule.markers.contains { fileManager.fileExists(atPath: project + "/" + $0) }
            }) else { return nil }
            return ProjectJunkItem(path: folder.path, size: folder.size, kind: rule.kind, project: project,
                                   lastTouched: lastTouched(project: project, fileManager: fileManager))
        }
        .sorted { $0.size > $1.size }
    }

    /// Newest change among the project's own top-level files (ignoring build and
    /// dependency folders), or the last git activity found up to 3 folders up.
    static func lastTouched(project: String, fileManager: FileManager) -> Date? {
        var newest: Date?
        func consider(_ date: Date?) {
            guard let date else { return }
            if newest == nil || date > newest! { newest = date }
        }
        if let entries = try? fileManager.contentsOfDirectory(atPath: project) {
            for entry in entries where !names.contains(entry) && entry != ".DS_Store" {
                consider((try? fileManager.attributesOfItem(atPath: project + "/" + entry))?[.modificationDate] as? Date)
            }
        }
        var dir = project
        for _ in 0..<4 {
            if let attrs = try? fileManager.attributesOfItem(atPath: dir + "/.git/index") {
                consider(attrs[.modificationDate] as? Date)
                break
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return newest
    }
}
