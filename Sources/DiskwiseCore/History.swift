import Foundation

public struct SpaceSample: Codable, Sendable, Equatable {
    public var date: Date
    public var available: Int64

    public init(date: Date, available: Int64) {
        self.date = date
        self.available = available
    }
}

/// Available space over the last 30 days, one sample per 15 minutes at most.
public struct SpaceHistory: Codable, Sendable, Equatable {
    public static let keepDays = 30
    public static let spacing: TimeInterval = 15 * 60

    public private(set) var samples: [SpaceSample] = []

    public init(samples: [SpaceSample] = []) { self.samples = samples }

    /// Adds a sample unless the last one is recent. Returns true when it was added.
    @discardableResult
    public mutating func record(_ available: Int64, at date: Date = Date()) -> Bool {
        if let last = samples.last, date.timeIntervalSince(last.date) < Self.spacing { return false }
        samples.append(SpaceSample(date: date, available: available))
        let cutoff = date.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        samples.removeAll { $0.date < cutoff }
        return true
    }

    public func recent(days: Int, now: Date = Date()) -> [SpaceSample] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return samples.filter { $0.date >= cutoff }
    }

    /// Change in available space over the window (negative when filling up).
    public func change(days: Int, now: Date = Date()) -> Int64? {
        let points = recent(days: days, now: now)
        guard let first = points.first, let last = points.last, first.date < last.date else { return nil }
        return last.available - first.available
    }

    public static func load(_ url: URL) -> SpaceHistory {
        guard let data = try? Data(contentsOf: url) else { return SpaceHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(SpaceHistory.self, from: data)) ?? SpaceHistory()
    }

    public func save(_ url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// Fires once when available space drops under the threshold, then waits
/// until there's a margin above it again before it can fire again.
public struct LowSpaceAlert: Codable, Sendable, Equatable {
    public var threshold: Int64
    public var margin: Int64
    public private(set) var armed = true

    public init(threshold: Int64 = 10 * Bytes.gb, margin: Int64 = 2 * Bytes.gb) {
        self.threshold = threshold
        self.margin = margin
    }

    public mutating func shouldAlert(available: Int64) -> Bool {
        if available >= threshold + margin { armed = true }
        guard armed, available < threshold else { return false }
        armed = false
        return true
    }
}
