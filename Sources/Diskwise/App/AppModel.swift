import AppKit
import DiskwiseCore

enum Page: Equatable {
    case home, cleanup, files, projects, apps
    /// Folder path components below home.
    case explore([String])
    /// App detail, by app path.
    case app(String)
}

/// An in-panel "are you sure" card.
struct Confirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: String
    let perform: () -> Void
}

/// Progress of a cleanup or project deletion, for the window's animated overlay.
struct CleaningState: Equatable {
    var total: Int64
    var freed: Int64 = 0
    var current = ""
    var finished = false
    var failed = 0
    var trashed = false
}

struct Toast: Equatable {
    let text: String
    var emptyTrash = false
}

/// Everything the panel shows, and the actions behind its buttons. Disk work
/// runs on background queues; results land here on the main thread.
@MainActor
final class AppModel: ObservableObject {
    @Published var disk: DiskInfo?
    @Published var fullDiskAccess = false

    @Published var groups: [CleanupGroup] = []
    @Published var cleanupLoading = false
    @Published var cleanupDate: Date?
    @Published var trashSize: Int64?
    @Published private(set) var selection: Set<String> = []

    @Published var scan: ScanResult?
    @Published var scanning = false
    @Published var scanProgress: ScanProgress?
    @Published var projects: [ProjectJunkItem] = []
    @Published var projectSelection: Set<String> = []
    @Published var downloads: [OldDownload] = []
    @Published var fileSelection: Set<String> = []

    @Published var apps: [InstalledApp] = []
    @Published var applicationsSize: Int64 = 0
    @Published var leftovers: [Leftover] = []
    @Published var leftoverSelection: Set<String> = []
    @Published var leftoversLoading = false

    @Published var history = SpaceHistory()
    /// Menu bar panel navigation.
    @Published var page: Page = .home
    /// Main window navigation.
    @Published var section: NavItem = .dashboard
    /// The app shown in the window's uninstaller detail.
    @Published var windowApp: String?
    @Published var cleaning: CleaningState?
    /// The Smart Care scan button was pressed this session.
    @Published private(set) var smartScanRequested = false
    @Published private var cleanupMeasured = 0
    @Published private var cleanupItemCount = 0
    @Published var busy: String?
    @Published var toast: Toast?
    @Published var confirmation: Confirmation?
    @Published var alertsOn: Bool {
        didSet {
            UserDefaults.standard.set(alertsOn, forKey: "alertsOn")
            if alertsOn { Notifier.requestPermission() }
        }
    }

    private let readOnly: Bool
    /// Cleanup sizing and removals, one at a time.
    private let work = DispatchQueue(label: "diskwise.work", qos: .userInitiated)
    /// The full home scan (minutes), kept off the cleanup queue.
    private let scanQueue = DispatchQueue(label: "diskwise.scan", qos: .utility)
    private var alert = LowSpaceAlert()
    private var timer: Timer?
    private var toastTask: Task<Void, Never>?
    /// Checkboxes the user changed by hand, kept across reloads.
    private var choices: [String: Bool] = [:]
    private var leftoversFor: String?

    init(readOnly: Bool = false) {
        self.readOnly = readOnly
        alertsOn = UserDefaults.standard.object(forKey: "alertsOn") as? Bool ?? true
    }

    // MARK: Lifecycle

    func start() {
        history = SpaceHistory.load(Store.historyURL)
        fullDiskAccess = Self.hasFullDiskAccess()
        refreshDisk()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDisk() }
        }
        loadCleanup()
        loadApps()
        if let cached = Store.loadScan() {
            scan = cached
            deriveFromScan(cached)
        }
        // The first scan waits for onboarding, so Full Disk Access can be granted before
        // macOS starts asking about single folders.
        if Preferences.shared.onboardingDone, scan.map({ Date().timeIntervalSince($0.date) > 12 * 3600 }) ?? true {
            startScan()
        }
        if alertsOn, !readOnly { Notifier.requestPermission() }
    }

    /// Called when the panel opens.
    func refreshIfStale() {
        refreshDisk()
        let access = Self.hasFullDiskAccess()
        if access != fullDiskAccess {
            fullDiskAccess = access
            loadCleanup()
            startScan()
            return
        }
        if cleanupDate.map({ Date().timeIntervalSince($0) > 15 * 60 }) ?? false { loadCleanup() }
        if !scanning, scan.map({ Date().timeIntervalSince($0.date) > 12 * 3600 }) ?? false { startScan() }
    }

    enum SmartPhase { case idle, scanning, done }

    var smartPhase: SmartPhase {
        guard smartScanRequested else { return .idle }
        return scanning || cleanupLoading ? .scanning : .done
    }

    /// Progress of a Smart Care scan: cleanup sizing, plus the folder scan when one runs.
    var smartProgress: Double {
        let cleanup = cleanupItemCount > 0 ? min(Double(cleanupMeasured) / Double(cleanupItemCount), 1) : (cleanupLoading ? 0 : 1)
        return scanning ? min(cleanup * 0.25 + scanFraction * 0.75, 0.99) : min(cleanup, 0.99)
    }

    /// Smart Care's Scan: re-measures every cleanup group, and rescans folders unless that
    /// happened in the last half hour.
    func smartScan() {
        smartScanRequested = true
        refreshDisk()
        loadCleanup()
        if scan.map({ Date().timeIntervalSince($0.date) > 30 * 60 }) ?? true {
            startScan()
        } else if let scan {
            deriveFromScan(scan)
        }
    }

    func refreshAll() {
        refreshDisk()
        loadCleanup()
        startScan()
    }

    func refreshDisk() {
        guard let info = DiskInfo.current() else { return }
        disk = info
        guard !readOnly else { return }
        if history.record(info.available) { history.save(Store.historyURL) }
        alert.threshold = Int64(Preferences.shared.alertThresholdGB) * Bytes.gb
        if alertsOn, alert.shouldAlert(available: info.available) { Notifier.lowSpace(info) }
    }

    // MARK: Cleanup

    func loadCleanup() {
        guard !cleanupLoading else { return }
        cleanupLoading = true
        let running = Self.runningApps()
        work.async { [weak self] in
            let listed = CleanupCatalog.list(running: running)
            let items = listed.flatMap(\.items)
            DispatchQueue.main.async {
                self?.cleanupItemCount = items.count
                self?.cleanupMeasured = 0
                self?.receive(listed)
            }
            DispatchQueue.concurrentPerform(iterations: items.count) { i in
                let size = CleanupCatalog.measure(items[i])
                DispatchQueue.main.async { self?.setSize(size, for: items[i].path) }
            }
            let trash = Trash.size()
            DispatchQueue.main.async { self?.finishCleanup(trash: trash) }
        }
    }

    private func receive(_ listed: [CleanupGroup]) {
        // Keep sizes we already know so the list doesn't flash spinners on reload.
        let known = Dictionary(groups.flatMap(\.items).compactMap { item in item.size.map { (item.path, $0) } },
                               uniquingKeysWith: { a, _ in a })
        groups = listed.map { group in
            var group = group
            for i in group.items.indices { group.items[i].size = known[group.items[i].path] }
            return group
        }
        updateSelection()
    }

    private func setSize(_ size: Int64, for path: String) {
        cleanupMeasured += 1
        for g in groups.indices {
            if let i = groups[g].items.firstIndex(where: { $0.path == path }) {
                groups[g].items[i].size = size
                return
            }
        }
    }

    private func finishCleanup(trash: Int64?) {
        for g in groups.indices { groups[g].items.removeAll { ($0.size ?? 1) == 0 } }
        groups.removeAll { $0.items.isEmpty }
        trashSize = trash
        cleanupLoading = false
        cleanupDate = Date()
        updateSelection()
    }

    private func updateSelection() {
        var chosen = Set<String>()
        for group in groups {
            for item in group.items where item.inUseBy == nil {
                if choices[item.path] ?? group.selectedByDefault { chosen.insert(item.path) }
            }
        }
        selection = chosen
    }

    func isSelected(_ item: CleanupItem) -> Bool { item.inUseBy == nil && selection.contains(item.path) }

    func toggle(_ item: CleanupItem) {
        guard item.inUseBy == nil else { return }
        choices[item.path] = !selection.contains(item.path)
        updateSelection()
    }

    /// Selects the whole group, or clears it when everything was selected.
    func toggle(_ group: CleanupGroup) {
        let usable = group.items.filter { $0.inUseBy == nil }
        let select = !usable.allSatisfy(isSelected)
        for item in usable { choices[item.path] = select }
        updateSelection()
    }

    func resetSelection() {
        choices = [:]
        updateSelection()
    }

    var selectedBytes: Int64 { groups.flatMap(\.items).filter(isSelected).reduce(0) { $0 + ($1.size ?? 0) } }
    var cleanupTotal: Int64 { groups.reduce(0) { $0 + $1.size } }
    var cleanupMeasuring: Bool { cleanupLoading && groups.contains(where: \.measuring) }

    func confirmClean() {
        let plan = groups.compactMap { group -> (removal: CleanupGroup.Removal, items: [CleanupItem], title: String)? in
            let items = group.items.filter(isSelected)
            return items.isEmpty ? nil : (group.removal, items, group.title)
        }
        guard !plan.isEmpty else { return }
        let items = plan.flatMap(\.items)
        let total = items.reduce(0) { $0 + ($1.size ?? 0) }
        var message = "Removes \(items.count) items from \(plan.count) \(plan.count == 1 ? "group" : "groups"). "
            + "Caches are deleted for good; apps and tools rebuild them when they need them."
        if plan.contains(where: { $0.removal == .trash }) { message += " Archives and backups go to the Trash." }
        if plan.contains(where: { $0.removal == .eraseSimulator || $0.removal == .wipeEmulator }) {
            message += " Simulators and emulators are reset."
        }
        confirmation = Confirmation(title: "Clean \(Bytes.format(total))?", message: message, action: "Clean") { [weak self] in
            self?.runClean(plan)
        }
    }

    private func runClean(_ plan: [(removal: CleanupGroup.Removal, items: [CleanupItem], title: String)]) {
        busy = "Cleaning..."
        cleaning = CleaningState(total: plan.flatMap(\.items).reduce(0) { $0 + ($1.size ?? 0) })
        work.async { [weak self] in
            var report = RemovalReport()
            for step in plan {
                for item in step.items {
                    DispatchQueue.main.async {
                        self?.busy = "Cleaning \(step.title)..."
                        self?.cleaning?.current = "\(step.title): \(item.name)"
                    }
                    let r = Remover.remove([item], removal: step.removal)
                    report.freed += r.freed
                    report.removed += r.removed
                    report.failed.merge(r.failed) { a, _ in a }
                    let freed = report.freed
                    DispatchQueue.main.async { self?.cleaning?.freed = freed }
                }
            }
            DispatchQueue.main.async { self?.finishRemoval(report, trashed: false) }
        }
    }

    func confirmEmptyTrash() {
        let size = trashSize.map { " (\(Bytes.format($0)))" } ?? ""
        confirmation = Confirmation(title: "Empty the Trash?", message: "Everything in the Trash\(size) is deleted for good.",
                                    action: "Empty Trash") { [weak self] in
            self?.busy = "Emptying the Trash..."
            DispatchQueue.global(qos: .userInitiated).async {
                let ok = Trash.empty()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.busy = nil
                    self.trashSize = ok ? 0 : self.trashSize
                    self.show(Toast(text: ok ? "Trash emptied." : "Couldn't empty the Trash. Allow Diskwise to control Finder in Settings."))
                    self.refreshDisk()
                }
            }
        }
    }

    // MARK: Scan

    func startScan() {
        guard !scanning else { return }
        scanning = true
        scanProgress = nil
        let options = Scanner.Options.standard(fullDiskAccess: fullDiskAccess)
        scanQueue.async { [weak self] in
            let result = Scanner.scan(home: NSHomeDirectory(), options: options, progress: { progress in
                DispatchQueue.main.async { self?.scanProgress = progress }
            })
            if let result { Store.saveScan(result) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                if let result {
                    self.scan = result
                    self.deriveFromScan(result)
                }
            }
        }
    }

    /// Project folders and old downloads, checked against the disk as it is now.
    private func deriveFromScan(_ result: ScanResult) {
        let junk = result.junk
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let projects = ProjectJunk.items(from: junk).filter { !SafeDelete.isExcluded($0.path) }
            let downloads = Downloads.old().filter { !SafeDelete.isExcluded($0.path) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.projects = projects
                self.projectSelection = Set(projects.filter { $0.isStale() }.map(\.path))
                self.downloads = downloads
            }
        }
    }

    var largeFiles: [LargeFile] { (scan?.largeFiles ?? []).filter { !SafeDelete.isExcluded($0.path) } }

    /// After Settings changes the excluded folders.
    func exclusionsChanged() {
        projects.removeAll { SafeDelete.isExcluded($0.path) }
        projectSelection = projectSelection.filter { !SafeDelete.isExcluded($0) }
        downloads.removeAll { SafeDelete.isExcluded($0.path) }
        fileSelection = fileSelection.filter { !SafeDelete.isExcluded($0) }
        loadCleanup()
    }

    /// How far the running scan is, estimated from the last scan's size.
    var scanFraction: Double {
        guard let progress = scanProgress else { return 0 }
        let expected = max(scan?.root.size ?? (disk.map { $0.used / 2 } ?? 1), 1)
        return min(Double(progress.bytes) / Double(expected), 0.99)
    }
    var staleProjects: [ProjectJunkItem] { projects.filter { $0.isStale() } }

    func confirmDeleteProjects() {
        let chosen = projects.filter { projectSelection.contains($0.path) }
        guard !chosen.isEmpty else { return }
        let total = chosen.reduce(0) { $0 + $1.size }
        confirmation = Confirmation(
            title: "Delete \(chosen.count) \(chosen.count == 1 ? "folder" : "folders") (\(Bytes.format(total)))?",
            message: "These dependency and build folders are deleted for good. Run npm install, pod install or a build to get them back.",
            action: "Delete") { [weak self] in
            self?.remove(chosen.map(\.path), sizes: chosen.map(\.size), mode: .delete)
        }
    }

    /// Moves user files (from Explore, Large files or Downloads) to the Trash.
    func confirmTrash(_ paths: [String], sizes: [Int64]) {
        guard !paths.isEmpty else { return }
        let total = sizes.reduce(0, +)
        let what = paths.count == 1 ? "\"\((paths[0] as NSString).lastPathComponent)\"" : "\(paths.count) items"
        confirmation = Confirmation(title: "Move \(what) to the Trash?",
                                    message: "Frees \(Bytes.format(total)) once you empty the Trash. You can put it back until then.",
                                    action: "Move to Trash") { [weak self] in
            self?.remove(paths, sizes: sizes, mode: .trash)
        }
    }

    private func remove(_ paths: [String], sizes: [Int64], mode: SafeDelete.Mode) {
        busy = mode == .trash ? "Moving to the Trash..." : "Deleting..."
        cleaning = CleaningState(total: sizes.reduce(0, +), trashed: mode == .trash)
        work.async { [weak self] in
            var report = RemovalReport()
            for (path, size) in zip(paths, sizes) {
                DispatchQueue.main.async { self?.cleaning?.current = (path as NSString).lastPathComponent }
                do {
                    if mode == .delete, !ProjectJunk.names.contains((path as NSString).lastPathComponent) {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    try SafeDelete.remove(path, mode: mode)
                    report.removed.append(path)
                    report.freed += size
                } catch {
                    report.failed[path] = error.localizedDescription
                }
                let freed = report.freed
                DispatchQueue.main.async { self?.cleaning?.freed = freed }
            }
            DispatchQueue.main.async { self?.finishRemoval(report, trashed: mode == .trash) }
        }
    }

    private func finishRemoval(_ report: RemovalReport, trashed: Bool) {
        busy = nil
        cleaning?.freed = report.freed
        cleaning?.failed = report.failed.count
        cleaning?.finished = true
        forget(report.removed)
        var text: String
        if trashed {
            text = "Moved \(Bytes.format(report.freed)) to the Trash."
        } else {
            text = report.freed > 0 ? "Freed \(Bytes.format(report.freed))." : "Nothing was removed."
        }
        if !report.failed.isEmpty { text += " \(report.failed.count) couldn't be removed." }
        show(Toast(text: text, emptyTrash: trashed && report.freed > 0))
        refreshDisk()
        loadCleanup()
    }

    /// Drops removed paths from the scan and the lists without a rescan.
    private func forget(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let removed = Set(paths)
        let prefix = NSHomeDirectory() + "/"
        if var result = scan {
            for path in paths where path.hasPrefix(prefix) {
                _ = result.root.remove(at: path.dropFirst(prefix.count).split(separator: "/").map(String.init))
            }
            result.largeFiles.removeAll { removed.contains($0.path) }
            result.junk.removeAll { removed.contains($0.path) }
            scan = result
            if !readOnly { Store.saveScan(result) }
        }
        projects.removeAll { removed.contains($0.path) }
        projectSelection.subtract(removed)
        downloads.removeAll { removed.contains($0.path) }
        fileSelection.subtract(removed)
    }

    // MARK: Apps

    func loadApps() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let list = AppInventory.list()
            DispatchQueue.main.async { self?.apps = list }
            DispatchQueue.concurrentPerform(iterations: list.count) { i in
                let size = DiskUsage().size(of: list[i].path)
                DispatchQueue.main.async {
                    guard let self, let j = self.apps.firstIndex(where: { $0.path == list[i].path }) else { return }
                    self.apps[j].size = size
                }
            }
            let all = DiskUsage().size(of: "/Applications") + DiskUsage().size(of: NSHomeDirectory() + "/Applications")
            DispatchQueue.main.async { self?.applicationsSize = all }
        }
    }

    /// Panel: shows the app's detail page.
    func openApp(_ app: InstalledApp) {
        page = .app(app.path)
        loadLeftovers(for: app)
    }

    func loadLeftovers(for app: InstalledApp) {
        leftoversFor = app.path
        leftovers = []
        leftoverSelection = []
        leftoversLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var found = AppInventory.leftovers(for: app).sorted { $0.kind < $1.kind }
            var sizes = [Int64](repeating: 0, count: found.count)
            let paths = found.map(\.path)
            sizes.withUnsafeMutableBufferPointer { buffer in
                DispatchQueue.concurrentPerform(iterations: paths.count) { i in buffer[i] = DiskUsage().size(of: paths[i]) }
            }
            for i in found.indices { found[i].size = sizes[i] }
            DispatchQueue.main.async {
                guard let self, self.leftoversFor == app.path else { return }
                self.leftovers = found
                self.leftoverSelection = Set(found.map(\.path))
                self.leftoversLoading = false
            }
        }
    }

    func confirmUninstall(_ app: InstalledApp) {
        let chosen = leftovers.filter { leftoverSelection.contains($0.path) }
        let total = (app.size ?? 0) + chosen.reduce(0) { $0 + ($1.size ?? 0) }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        var message = "Moves \(app.name)"
        message += chosen.isEmpty ? " to the Trash (\(Bytes.format(total)))." : " and \(chosen.count) related items to the Trash (\(Bytes.format(total)))."
        if !running.isEmpty { message += " \(app.name) is open and will be quit first." }
        confirmation = Confirmation(title: "Uninstall \(app.name)?", message: message, action: "Uninstall") { [weak self] in
            self?.runUninstall(app, leftovers: chosen, running: running, total: total)
        }
    }

    private func runUninstall(_ app: InstalledApp, leftovers: [Leftover], running: [NSRunningApplication], total: Int64) {
        busy = "Uninstalling \(app.name)..."
        running.forEach { $0.terminate() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for _ in 0..<50 where !running.allSatisfy(\.isTerminated) { Thread.sleep(forTimeInterval: 0.1) }
            var failed: [String] = []
            if let reason = SafeDelete.appRefusal(for: app.path) {
                failed.append(reason)
            } else {
                do { try Trash.move(app.path) } catch { failed.append(app.name) }
            }
            for item in leftovers {
                do { try SafeDelete.remove(item.path, mode: .trash) } catch { failed.append(item.name) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = nil
                if FileManager.default.fileExists(atPath: app.path) {
                    self.show(Toast(text: "Couldn't move \(app.name) to the Trash."))
                    return
                }
                self.apps.removeAll { $0.path == app.path }
                if self.page == .app(app.path) { self.page = .apps }
                if self.windowApp == app.path { self.windowApp = nil }
                var text = "Moved \(app.name) (\(Bytes.format(total))) to the Trash."
                if failed.count > 0 { text += " \(failed.count) items couldn't be moved." }
                self.show(Toast(text: text, emptyTrash: true))
            }
        }
    }

    // MARK: Breakdown and helpers

    var breakdown: [(StorageCategory, Int64)] {
        guard let disk else { return [] }
        var cleanable = groups.flatMap(\.items).filter(isSelected).compactMap { item in item.size.map { (path: item.path, size: $0) } }
        cleanable += staleProjects.map { (path: $0.path, size: $0.size) }
        return Breakdown.compute(disk: disk, home: scan?.root, apps: applicationsSize, cleanable: cleanable)
    }

    var cleanableBytes: Int64 { selectedBytes + staleProjects.reduce(0) { $0 + $1.size } }

    func show(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func back() {
        switch page {
        case .explore(let parts) where !parts.isEmpty: page = .explore(Array(parts.dropLast()))
        case .app: page = .apps
        default: page = .home
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    static func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy != .prohibited, let id = app.bundleIdentifier else { return nil }
            return RunningApp(name: app.localizedName ?? id, bundleID: id)
        }
    }

    /// The TCC database can only be opened with Full Disk Access (and trying never prompts).
    static func hasFullDiskAccess() -> Bool {
        let fd = open(NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }
}

/// Files in ~/Library/Application Support/Diskwise.
enum Store {
    static let folder = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Diskwise")
    static var historyURL: URL { folder.appendingPathComponent("history.json") }
    static var scanURL: URL { folder.appendingPathComponent("scan.json") }

    static func loadScan() -> ScanResult? {
        guard let data = try? Data(contentsOf: scanURL) else { return nil }
        return try? JSONDecoder().decode(ScanResult.self, from: data)
    }

    static func saveScan(_ result: ScanResult) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(result).write(to: scanURL, options: .atomic)
    }
}
