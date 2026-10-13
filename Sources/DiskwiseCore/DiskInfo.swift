import Foundation

/// Capacity of the volume holding the home folder.
public struct DiskInfo: Equatable, Codable, Sendable {
    public var name: String
    public var total: Int64
    /// What macOS reports as available, including purgeable space it frees on demand
    /// (the number Finder and System Settings show).
    public var available: Int64
    /// Space that is free right now, without purging anything.
    public var free: Int64

    public init(name: String, total: Int64, available: Int64, free: Int64) {
        self.name = name
        self.total = total
        self.available = available
        self.free = free
    }

    public var used: Int64 { max(total - available, 0) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    public var usedPercent: Int { Int((usedFraction * 100).rounded()) }
    public var purgeable: Int64 { max(available - free, 0) }

    public static func current(path: String = NSHomeDirectory()) -> DiskInfo? {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        let free = Int64(values.volumeAvailableCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage ?? free
        return DiskInfo(name: values.volumeLocalizedName ?? "Macintosh HD", total: Int64(total),
                        available: max(available, free), free: free)
    }
}
