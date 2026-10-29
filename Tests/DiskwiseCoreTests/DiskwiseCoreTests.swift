import XCTest
@testable import DiskwiseCore

/// A throwaway home folder for each test.
final class FakeHome {
    let path: String
    let fm = FileManager.default

    init() {
        let base = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
        path = base + "/diskwise-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit { try? fm.removeItem(atPath: path) }

    @discardableResult
    func file(_ relative: String, bytes: Int = 10_000) -> String {
        let full = path + "/" + relative
        try? fm.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: full, contents: Data(repeating: 7, count: bytes))
        return full
    }

    func dir(_ relative: String) {
        try? fm.createDirectory(atPath: path + "/" + relative, withIntermediateDirectories: true)
    }

    func exists(_ relative: String) -> Bool { fm.fileExists(atPath: path + "/" + relative) }
}

final class BytesTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(Bytes.format(0), "0 KB")
        XCTAssertEqual(Bytes.format(640_000), "640 KB")
        XCTAssertEqual(Bytes.format(12_400_000), "12.4 MB")
        XCTAssertEqual(Bytes.format(13_200_000_000), "13.2 GB")
        XCTAssertEqual(Bytes.format(494_000_000_000), "494 GB")
        XCTAssertEqual(Bytes.format(1_200_000_000_000), "1.2 TB")
    }

    func testAge() {
        let now = Date()
        XCTAssertEqual(ageText(now.addingTimeInterval(-3600), now: now), "today")
        XCTAssertEqual(ageText(now.addingTimeInterval(-5 * 86_400), now: now), "5 days ago")
        XCTAssertEqual(ageText(now.addingTimeInterval(-95 * 86_400), now: now), "3 months ago")
        XCTAssertEqual(ageText(nil, now: now), "never")
    }
}

final class SafeDeleteTests: XCTestCase {
    func testRefusesOutsideHomeAndProtectedFolders() {
        let home = FakeHome()
        XCTAssertNotNil(SafeDelete.refusal(for: "/etc/hosts", home: home.path))
        XCTAssertNotNil(SafeDelete.refusal(for: home.path, home: home.path))
        XCTAssertNotNil(SafeDelete.refusal(for: home.path + "/Library/Caches", home: home.path))
        XCTAssertNotNil(SafeDelete.refusal(for: home.path + "/Documents", home: home.path))
        XCTAssertNotNil(SafeDelete.refusal(for: home.path + "/.ssh/id_rsa", home: home.path))
        XCTAssertNotNil(SafeDelete.refusal(for: home.path + "/Library/Caches/../../..", home: home.path))
        XCTAssertNotNil(SafeDelete.refusal(for: "relative/path", home: home.path))
        XCTAssertNil(SafeDelete.refusal(for: home.path + "/Library/Caches/com.spotify.client", home: home.path))
        XCTAssertNil(SafeDelete.refusal(for: home.path + "/.npm/_cacache", home: home.path))
    }

    func testRefusesPathsThatEscapeThroughALink() throws {
        let home = FakeHome()
        let outside = FakeHome()
        outside.file("victim/data.bin")
        try FileManager.default.createSymbolicLink(atPath: home.path + "/link", withDestinationPath: outside.path + "/victim")
        XCTAssertNotNil(SafeDelete.refusal(for: home.path + "/link/data.bin", home: home.path))
        // The link itself may go; that never touches its target.
        XCTAssertNil(SafeDelete.refusal(for: home.path + "/link", home: home.path))
        try SafeDelete.remove(home.path + "/link", mode: .delete, home: home.path)
        XCTAssertTrue(outside.exists("victim/data.bin"))
    }

    func testRemoveDeletesFolder() throws {
        let home = FakeHome()
        home.file(".npm/_cacache/a/b.bin")
        try SafeDelete.remove(home.path + "/.npm/_cacache", mode: .delete, home: home.path)
        XCTAssertFalse(home.exists(".npm/_cacache"))
        XCTAssertTrue(home.exists(".npm"))
        XCTAssertThrowsError(try SafeDelete.remove(home.path + "/.npm", mode: .delete, home: home.path))
    }
}

final class ScannerTests: XCTestCase {
    func testTreeSizesJunkAndLargeFiles() throws {
        let home = FakeHome()
        home.file("Movies/big.mov", bytes: 3_000_000)
        home.file("Movies/small.txt", bytes: 1000)
        home.file("Projects/web/package.json", bytes: 100)
        home.file("Projects/web/node_modules/react/index.js", bytes: 2_000_000)
        home.file("Projects/web/node_modules/react/node_modules/x/huge.bin", bytes: 2_000_000)
        home.file("Library/Caches/app/cache.db", bytes: 1_500_000)
        home.file("Library/CloudStorage/Drive/file.bin", bytes: 5_000_000)
        home.file(".vscode/extensions/ext/node_modules/y/a.js", bytes: 1_000_000)

        var options = Scanner.Options()
        options.keepSize = 500_000
        options.largeFileSize = 1_000_000
        let result = try XCTUnwrap(Scanner.scan(home: home.path, options: options))

        let movies = try XCTUnwrap(result.root.child(named: "Movies"))
        XCTAssertGreaterThanOrEqual(movies.size, 3_000_000)
        XCTAssertEqual(movies.child(named: "big.mov")?.isDirectory, false)
        XCTAssertEqual(movies.restCount, 1)
        XCTAssertNotNil(result.root.node(at: "Library/Caches/app"))
        XCTAssertNil(result.root.node(at: "Library/CloudStorage"), "cloud folders are never entered")

        // One junk folder per project (nested node_modules are inside it), none in hidden folders.
        XCTAssertEqual(result.junk.map(\.path), [home.path + "/Projects/web/node_modules"])
        XCTAssertGreaterThanOrEqual(result.junk[0].size, 4_000_000)

        // Large files: only the user's own, not dependencies or Library.
        XCTAssertEqual(result.largeFiles.map(\.name), ["big.mov"])
        XCTAssertEqual(result.root.size, DiskUsage().size(of: home.path) - (DiskUsage().size(of: home.path + "/Library/CloudStorage")),
                       accuracy: 64_000)
    }

    func testHardLinksCountOnce() throws {
        let home = FakeHome()
        let a = home.file("a/one.bin", bytes: 1_000_000)
        home.dir("b")
        try FileManager.default.linkItem(atPath: a, toPath: home.path + "/b/two.bin")
        let size = DiskUsage().size(of: home.path)
        XCTAssertLessThan(size, 1_500_000)
    }

    func testRemoveShrinksParents() {
        var root = FolderNode(name: "/home", size: 100, isDirectory: true, children: [
            FolderNode(name: "a", size: 80, isDirectory: true, children: [FolderNode(name: "b", size: 50, isDirectory: false)]),
        ])
        XCTAssertEqual(root.remove(at: ["a", "b"]), 50)
        XCTAssertEqual(root.size, 50)
        XCTAssertEqual(root.child(named: "a")?.size, 30)
        XCTAssertEqual(root.remove(at: ["missing"]), 0)
    }
}

final class ProjectJunkTests: XCTestCase {
    func testNeedsMarkerAndReportsProject() {
        let home = FakeHome()
        home.file("p/app/build.gradle")
        home.file("p/app/build/out.apk", bytes: 5000)
        home.file("p/notes/build/readme.txt")
        let items = ProjectJunk.items(from: [JunkFolder(path: home.path + "/p/app/build", size: 5000),
                                             JunkFolder(path: home.path + "/p/notes/build", size: 10)])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].projectName, "p › app")
        XCTAssertEqual(items[0].kind, "Gradle/Flutter build")
        XCTAssertNotNil(items[0].lastTouched)
        XCTAssertFalse(items[0].isStale())
    }

    func testEligibility() {
        XCTAssertTrue(ProjectJunk.eligible("My Projects/site/node_modules"))
        XCTAssertFalse(ProjectJunk.eligible(".nvm/versions/node/lib/node_modules"))
        XCTAssertFalse(ProjectJunk.eligible("Library/Application Support/Code/node_modules"))
        XCTAssertFalse(ProjectJunk.eligible("Projects/Tool.app/Contents/node_modules"))
        XCTAssertFalse(ProjectJunk.eligible("node_modules"))
    }

    func testStaleness() {
        let now = Date()
        var item = ProjectJunkItem(path: "/x/node_modules", size: 1, kind: "", project: "/x",
                                   lastTouched: now.addingTimeInterval(-40 * 86_400))
        XCTAssertTrue(item.isStale(now: now))
        item.lastTouched = now.addingTimeInterval(-3 * 86_400)
        XCTAssertFalse(item.isStale(now: now))
    }
}

final class CleanupTests: XCTestCase {
    func testListsGroupsWithoutDoubleCounting() {
        let home = FakeHome()
        home.file("Library/Caches/com.spotify.client/data", bytes: 2000)
        home.file("Library/Caches/Homebrew/downloads/x.tar", bytes: 2000)
        home.file("Library/Caches/com.apple.Safari/x", bytes: 2000)
        home.file("Library/Caches/Google/Chrome/x", bytes: 2000)
        home.file(".npm/_cacache/index", bytes: 2000)
        home.file(".cache/huggingface/hub/models--meta--llama/x", bytes: 2000)
        home.file(".cache/othertool/x", bytes: 2000)

        let running = [RunningApp(name: "Google Chrome", bundleID: "com.google.Chrome")]
        let groups = CleanupCatalog.list(home: home.path, running: running)
        func group(_ id: String) -> CleanupGroup? { groups.first { $0.id == id } }

        let caches = group("app-caches")?.items.map(\.name) ?? []
        XCTAssertEqual(Set(caches), ["com.spotify.client", "Google"], "Homebrew belongs to dev caches, Apple's caches are left alone")
        XCTAssertEqual(group("app-caches")?.items.first { $0.name == "Google" }?.inUseBy, "Google Chrome")
        XCTAssertEqual(group("dev")?.items.map(\.name), ["Homebrew"])
        XCTAssertEqual(group("npm")?.items.count, 1)
        XCTAssertEqual(group("models")?.items.map(\.name), ["meta/llama"])
        XCTAssertEqual(group("dotcache")?.items.map(\.name), ["othertool"])
        XCTAssertNil(group("gradle"), "groups with nothing on disk are hidden")
    }

    func testRemoverSkipsOpenAppsAndCountsFreed() {
        let home = FakeHome()
        home.file("Library/Caches/a/x", bytes: 5000)
        home.file("Library/Caches/b/x", bytes: 5000)
        let items = [CleanupItem(path: home.path + "/Library/Caches/a", name: "a", source: "Caches", size: 5000),
                     CleanupItem(path: home.path + "/Library/Caches/b", name: "b", source: "Caches", size: 5000, inUseBy: "B")]
        let report = Remover.remove(items, removal: .delete, home: home.path)
        XCTAssertEqual(report.freed, 5000)
        XCTAssertFalse(home.exists("Library/Caches/a"))
        XCTAssertTrue(home.exists("Library/Caches/b"))
    }

    func testOwnerMatching() {
        let running = [RunningApp(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
                       RunningApp(name: "Finder", bundleID: "com.apple.finder")]
        XCTAssertEqual(CleanupCatalog.owner(of: "com.todesktop.230313mzl4w4u92.ShipIt", running: running), "Cursor")
        XCTAssertEqual(CleanupCatalog.owner(of: "Cursor", running: running), "Cursor")
        XCTAssertNil(CleanupCatalog.owner(of: "Apple", running: running))
        XCTAssertNil(CleanupCatalog.owner(of: "com.spotify.client", running: running))
    }
}

final class AppsTests: XCTestCase {
    func testLeftoversMatchByBundleID() {
        let home = FakeHome()
        home.file("Library/Preferences/com.acme.Rocket.plist")
        home.file("Library/Caches/com.acme.Rocket/x")
        home.file("Library/Caches/com.acme.RocketHelper/x")
        home.file("Library/Application Support/Rocket/x")
        home.file("Library/Group Containers/ABCDE12345.com.acme.Rocket/x")
        home.file("Library/Containers/com.acme.Rocket.Extension/x")
        home.file("Library/Caches/com.other.App/x")
        let app = InstalledApp(path: "/Applications/Rocket.app", name: "Rocket", bundleID: "com.acme.Rocket", version: "1")
        let found = Set(AppInventory.leftovers(for: app, home: home.path).map { "\($0.kind)/\($0.name)" })
        XCTAssertEqual(found, ["Preferences/com.acme.Rocket.plist", "Caches/com.acme.Rocket",
                               "Application Support/Rocket", "Group Containers/ABCDE12345.com.acme.Rocket",
                               "Containers/com.acme.Rocket.Extension"])
    }

    func testAppRefusal() {
        XCTAssertNotNil(SafeDelete.appRefusal(for: "/System/Applications/Notes.app"))
        XCTAssertNotNil(SafeDelete.appRefusal(for: "/Applications/Safari.app"))
        XCTAssertNotNil(SafeDelete.appRefusal(for: "/Applications/Thing.txt"))
    }
}

final class HistoryTests: XCTestCase {
    func testSpacingAndTrimming() {
        var history = SpaceHistory()
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(history.record(100, at: start))
        XCTAssertFalse(history.record(90, at: start.addingTimeInterval(60)))
        XCTAssertTrue(history.record(80, at: start.addingTimeInterval(16 * 60)))
        XCTAssertEqual(history.change(days: 1, now: start.addingTimeInterval(20 * 60)), -20)
        history.record(70, at: start.addingTimeInterval(31 * 86_400))
        XCTAssertEqual(history.samples.map(\.available), [70])
    }

    func testAlertFiresOnceUntilRecovered() {
        var alert = LowSpaceAlert(threshold: 10, margin: 2)
        XCTAssertFalse(alert.shouldAlert(available: 15))
        XCTAssertTrue(alert.shouldAlert(available: 9))
        XCTAssertFalse(alert.shouldAlert(available: 8))
        XCTAssertFalse(alert.shouldAlert(available: 11))
        XCTAssertFalse(alert.shouldAlert(available: 9))
        XCTAssertFalse(alert.shouldAlert(available: 12))
        XCTAssertTrue(alert.shouldAlert(available: 5))
    }
}

final class BreakdownTests: XCTestCase {
    func testCategoriesDontOverlap() {
        let disk = DiskInfo(name: "HD", total: 1000, available: 100, free: 100)
        let home = FolderNode(name: "/h", size: 500, isDirectory: true, children: [
            FolderNode(name: "Library", size: 300, isDirectory: true),
            FolderNode(name: "Documents", size: 50, isDirectory: true),
        ])
        let parts = Dictionary(uniqueKeysWithValues: Breakdown.compute(
            disk: disk, home: home, homePath: "/h", apps: 100,
            cleanable: [("/h/Library/Caches", 120), ("/h/.npm/_cacache", 30)]))
        XCTAssertEqual(parts[.cleanable], 150)
        XCTAssertEqual(parts[.library], 180)
        XCTAssertEqual(parts[.documents], 50)
        XCTAssertEqual(parts[.projects], 120)
        XCTAssertEqual(parts[.apps], 100)
        XCTAssertEqual(parts.values.reduce(0, +), disk.used)
    }
}

final class EmulatorTests: XCTestCase {
    func testWipeKeepsTheEmulator() {
        let home = FakeHome()
        home.file(".android/avd/Pixel_7.avd/config.ini", bytes: 100)
        home.file(".android/avd/Pixel_7.avd/userdata-qemu.img", bytes: 50_000)
        home.file(".android/avd/Pixel_7.avd/snapshots/default_boot/ram.img", bytes: 50_000)
        home.file(".android/avd/Pixel_7.ini", bytes: 100)
        let group = CleanupCatalog.list(home: home.path).first { $0.id == "emulators" }
        XCTAssertEqual(group?.items.map(\.name), ["Pixel 7"])
        var item = group!.items[0]
        item.size = DiskUsage().size(of: item.path)
        let report = Remover.remove([item], removal: .wipeEmulator, home: home.path)
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertGreaterThan(report.freed, 90_000)
        XCTAssertTrue(home.exists(".android/avd/Pixel_7.avd/config.ini"))
        XCTAssertFalse(home.exists(".android/avd/Pixel_7.avd/userdata-qemu.img"))
        XCTAssertFalse(home.exists(".android/avd/Pixel_7.avd/snapshots"))
    }
}

final class ExclusionTests: XCTestCase {
    override func tearDown() { SafeDelete.excluded = [] }

    func testExcludedFoldersAreNeverListedOrRemoved() {
        let home = FakeHome()
        home.file("Library/Caches/com.keep.me/x", bytes: 2000)
        home.file("Library/Caches/com.spotify.client/x", bytes: 2000)
        home.file("Library/Caches/Google/Chrome/Profile/x", bytes: 2000)
        SafeDelete.excluded = [home.path + "/Library/Caches/com.keep.me", home.path + "/Library/Caches/Google/Chrome/Profile"]
        let caches = CleanupCatalog.list(home: home.path).first { $0.id == "app-caches" }?.items.map(\.name) ?? []
        XCTAssertEqual(caches, ["com.spotify.client"], "excluded folders and folders containing them are left out")
        XCTAssertNotNil(SafeDelete.refusal(for: home.path + "/Library/Caches/com.keep.me/x", home: home.path))
        XCTAssertNotNil(SafeDelete.refusal(for: home.path + "/Library/Caches/Google", home: home.path))
        XCTAssertNil(SafeDelete.refusal(for: home.path + "/Library/Caches/com.spotify.client", home: home.path))
    }

    func testRemoveKeepsChildrenSorted() {
        var root = FolderNode(name: "/h", size: 300, isDirectory: true, children: [
            FolderNode(name: "a", size: 200, isDirectory: true, children: [FolderNode(name: "x", size: 190, isDirectory: false)]),
            FolderNode(name: "b", size: 100, isDirectory: true),
        ])
        _ = root.remove(at: ["a", "x"])
        XCTAssertEqual(root.children.map(\.name), ["b", "a"])
    }
}

final class SafetyTests: XCTestCase {
    override func tearDown() { SafeDelete.excluded = [] }

    func testVerdicts() {
        let home = FakeHome()
        home.file("Library/Caches/com.spotify.client/x")
        home.file("Projects/site/package.json")
        home.file("Projects/site/node_modules/react/index.js")
        home.file("Projects/site/src/app.js")
        home.file("Documents/tax.pdf")
        func safety(_ relative: String) -> Safety { SafetyAdvisor.verdict(for: home.path + "/" + relative, home: home.path).safety }

        XCTAssertEqual(safety("Library/Caches/com.spotify.client"), .safe)
        XCTAssertEqual(safety(".npm/_cacache"), .safe)
        XCTAssertEqual(safety("Projects/site/node_modules"), .safe)
        XCTAssertEqual(safety("Projects/site/node_modules/react/index.js"), .safe)
        XCTAssertEqual(safety("Library/Developer/CoreSimulator/Devices/ABC"), .review)
        XCTAssertEqual(safety("Documents/tax.pdf"), .review)
        XCTAssertEqual(safety("Projects/site/src"), .review)
        XCTAssertEqual(safety("Library/Application Support/SomeApp"), .unsafe)
        XCTAssertEqual(safety("Library/Application Support/Code/Cache"), .safe, "an Electron cache inside app data")
        XCTAssertEqual(safety("Library/Caches"), .safe, "the caches folder is covered by app caches")
        XCTAssertEqual(safety("Library"), .unsafe)
        XCTAssertEqual(safety(".ssh/id_rsa"), .unsafe)
        XCTAssertEqual(safety("Projects/site/.git"), .unsafe)
        XCTAssertEqual(SafetyAdvisor.verdict(for: "/etc/hosts", home: home.path).safety, .unsafe)
        SafeDelete.excluded = [home.path + "/Documents"]
        XCTAssertEqual(safety("Documents/tax.pdf"), .unsafe)
    }

    func testGroupsAndLeftovers() {
        XCTAssertEqual(SafetyAdvisor.verdict(forGroup: "npm").safety, .safe)
        XCTAssertEqual(SafetyAdvisor.verdict(forGroup: "models").safety, .review)
        XCTAssertEqual(SafetyAdvisor.verdict(forLeftoverKind: "Caches").safety, .safe)
        XCTAssertEqual(SafetyAdvisor.verdict(forLeftoverKind: "Application Support").safety, .review)
    }
}

final class SystemStatsTests: XCTestCase {
    func testCPUUsageFromTickChange() {
        let before = CPUTicks(busy: 1_000, idle: 9_000)
        let after = CPUTicks(busy: 1_300, idle: 9_700)
        XCTAssertEqual(CPUTicks.usage(from: before, to: after)!, 0.3, accuracy: 0.0001)
        XCTAssertNil(CPUTicks.usage(from: after, to: after), "no ticks passed")
        XCTAssertNil(CPUTicks.usage(from: after, to: before), "counters went backwards")
    }

    func testMemoryUsedLikeActivityMonitor() {
        // App memory (internal minus purgeable) + wired + compressed.
        let used = MemoryStats.used(pageSize: 16_384, internal: 500_000, purgeable: 20_000, wired: 300_000, compressed: 100_000)
        XCTAssertEqual(used, Int64(880_000) * 16_384)
        XCTAssertEqual(MemoryStats.used(pageSize: 16_384, internal: 10, purgeable: 50, wired: 0, compressed: 0), 0)
    }

    func testMemoryFormatUsesBinaryGigabytes() {
        XCTAssertEqual(Bytes.formatMemory(24 * 1_073_741_824), "24 GB")
        XCTAssertEqual(Bytes.formatMemory(15_246_000_000), "14.2 GB")
        XCTAssertEqual(Bytes.formatMemory(900 * 1_048_576), "900 MB")
    }

    func testDieTemperatureAveragesOnlyDieSensors() {
        let readings: [(String, Double)] = [
            ("PMU tdie1", 62), ("PMU tdie2", 58), ("PMU tdev1", -9202.9),
            ("NAND CH0 temp", 49), ("PMU tdie3", 0), ("PMU tdie4", 300),
        ]
        XCTAssertEqual(Thermals.dieTemperature(readings)!, 60, accuracy: 0.0001)
        XCTAssertNil(Thermals.dieTemperature([("NAND CH0 temp", 49)]))
    }

    func testBatteryFromRegistry() {
        let registry: [String: Any] = [
            "CycleCount": 315, "CurrentCapacity": 38, "MaxCapacity": 100,
            "IsCharging": true, "ExternalConnected": true, "FullyCharged": false,
            "BatteryData": ["NominalChargeCapacity": 5456, "DesignCapacity": 6249],
        ]
        let battery = BatteryInfo(registry: registry, health: nil)!
        XCTAssertEqual(battery.cycles, 315)
        XCTAssertEqual(battery.charge, 38)
        XCTAssertTrue(battery.charging)
        XCTAssertEqual(battery.health, 87, "falls back to nominal over design capacity")
        XCTAssertEqual(BatteryInfo(registry: registry, health: BatteryHealth(percent: 90, condition: "Good"))!.health, 90)
        XCTAssertNil(BatteryInfo(registry: [:], health: nil), "desktop Macs have no battery")
    }

    func testBatteryHealthFromSystemProfiler() {
        let json = """
        {"SPPowerDataType":[{"_name":"spbattery_information","sppower_battery_health_info":
        {"sppower_battery_cycle_count":315,"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"90%"}}]}
        """
        XCTAssertEqual(BatteryHealth(profilerJSON: Data(json.utf8)), BatteryHealth(percent: 90, condition: "Good"))
        XCTAssertNil(BatteryHealth(profilerJSON: Data(#"{"SPPowerDataType":[]}"#.utf8)))
    }
}
