import SwiftUI
import DiskwiseCore

/// One look for the panel: background glass, raised surfaces and the accent.
/// Text and status colors are shared by every look.
struct Palette {
    let name: String
    let glassTop: Color
    let glassBottom: Color
    let glassOpacity: Double
    let raised: Color
    let accent: Color
    let onAccent: Color

    /// Deep ocean blue glass with a cyan accent.
    static let ocean = Palette(
        name: "Ocean", glassTop: Color(red: 0.09, green: 0.29, blue: 0.60), glassBottom: Color(red: 0.03, green: 0.11, blue: 0.30),
        glassOpacity: 0.84, raised: Color(red: 0.08, green: 0.22, blue: 0.44),
        accent: Color(red: 0.38, green: 0.86, blue: 0.97), onAccent: Color(red: 0.03, green: 0.10, blue: 0.22))

    /// Dark navy, close to black at the bottom, with a bright blue accent.
    static let midnight = Palette(
        name: "Midnight", glassTop: Color(red: 0.08, green: 0.15, blue: 0.32), glassBottom: Color(red: 0.02, green: 0.05, blue: 0.13),
        glassOpacity: 0.88, raised: Color(red: 0.09, green: 0.15, blue: 0.29),
        accent: Color(red: 0.36, green: 0.66, blue: 1.0), onAccent: .white)

    /// Brighter royal blue with a light sky accent.
    static let royal = Palette(
        name: "Royal", glassTop: Color(red: 0.17, green: 0.38, blue: 0.88), glassBottom: Color(red: 0.07, green: 0.17, blue: 0.55),
        glassOpacity: 0.84, raised: Color(red: 0.13, green: 0.28, blue: 0.66),
        accent: Color(red: 0.62, green: 0.90, blue: 1.0), onAccent: Color(red: 0.04, green: 0.12, blue: 0.35))

    /// Neutral slate with a blue tint, like iStat Menus.
    static let slate = Palette(
        name: "Slate blue", glassTop: Color(red: 0.16, green: 0.21, blue: 0.31), glassBottom: Color(red: 0.07, green: 0.09, blue: 0.15),
        glassOpacity: 0.86, raised: Color(red: 0.15, green: 0.19, blue: 0.28),
        accent: Color(red: 0.30, green: 0.62, blue: 1.0), onAccent: .white)

    static let all: [Palette] = [.ocean, .midnight, .royal, .slate]
}

enum Theme {
    static var current = Palette.midnight

    static var glassTop: Color { current.glassTop }
    static var glassBottom: Color { current.glassBottom }
    static var glassOpacity: Double { current.glassOpacity }
    static var raised: Color { current.raised }
    /// Buttons, checkboxes, links and bars.
    static var cyan: Color { current.accent }
    static var onCyan: Color { current.onAccent }

    static let text = Color.white
    static let secondary = Color.white.opacity(0.64)
    static let tertiary = Color.white.opacity(0.42)

    static let card = Color.white.opacity(0.07)
    static let tile = Color.white.opacity(0.06)
    static let border = Color.white.opacity(0.10)
    static let track = Color.white.opacity(0.13)
    static let hover = Color.white.opacity(0.07)
    static let shade = Color.black.opacity(0.16)

    static let green = Color(red: 0.45, green: 0.93, blue: 0.56)
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.32)
    static let red = Color(red: 1.0, green: 0.45, blue: 0.55)
    static let blue = Color(red: 0.47, green: 0.67, blue: 1.0)
    static let violet = Color(red: 0.76, green: 0.62, blue: 1.0)
    static let teal = Color(red: 0.22, green: 0.90, blue: 0.78)
    static let pink = Color(red: 1.0, green: 0.52, blue: 0.82)
    static let gray = Color.white.opacity(0.42)

    static func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension StorageCategory {
    var color: Color {
        switch self {
        case .cleanable: return Theme.cyan
        case .apps: return Theme.violet
        case .documents: return Theme.pink
        case .projects: return Theme.amber
        case .library: return Theme.teal
        case .system: return Theme.gray
        }
    }
}

/// How full the disk is, by space left (GB matter more than percent on a full disk).
enum SpaceLevel {
    case fine, low, critical

    init(available: Int64) {
        if available < 10 * Bytes.gb { self = .critical } else if available < 20 * Bytes.gb { self = .low } else { self = .fine }
    }

    var color: Color {
        switch self {
        case .fine: return Theme.green
        case .low: return Theme.amber
        case .critical: return Theme.red
        }
    }

    var ringColors: (Color, Color) {
        switch self {
        case .fine: return (Theme.teal, Theme.green)
        case .low: return (Theme.amber, Color(red: 1, green: 0.55, blue: 0.25))
        case .critical: return (Theme.pink, Theme.red)
        }
    }
}
