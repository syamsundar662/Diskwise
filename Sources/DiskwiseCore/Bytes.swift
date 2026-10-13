import Foundation

/// Byte counts as Finder shows them (decimal units: 1 GB = 1,000,000,000 bytes).
public enum Bytes {
    public static let kb: Int64 = 1_000
    public static let mb: Int64 = 1_000_000
    public static let gb: Int64 = 1_000_000_000

    /// "0 KB", "640 KB", "12.4 MB", "13.2 GB", "494 GB", "1.2 TB".
    public static func format(_ bytes: Int64) -> String {
        let value = Double(max(bytes, 0))
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6)]
        for (unit, size) in units where value >= size * 0.995 {
            let n = value / size
            return n >= 99.5 ? "\(Int(n.rounded())) \(unit)" : String(format: "%.1f %@", n, unit)
        }
        return "\(Int((value / 1e3).rounded())) KB"
    }
}

/// "today", "yesterday", "5 days ago", "3 months ago", "2 years ago".
public func ageText(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "never" }
    let days = Int(now.timeIntervalSince(date) / 86_400)
    switch days {
    case ..<1: return "today"
    case 1: return "yesterday"
    case 2..<31: return "\(days) days ago"
    case 31..<365:
        let months = days / 30
        return months == 1 ? "1 month ago" : "\(months) months ago"
    default:
        let years = days / 365
        return years == 1 ? "1 year ago" : "\(years) years ago"
    }
}
