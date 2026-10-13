import SwiftUI
import DiskwiseCore

// Pieces shared by the main window's pages.

enum NavItem: String, CaseIterable, Identifiable {
    case dashboard = "Smart Care"
    case cleanup = "Cleanup"
    case lens = "Space Lens"
    case files = "Large & Old Files"
    case projects = "Project Junk"
    case apps = "Uninstaller"
    case activity = "Activity"

    var id: String { rawValue }

    /// Sections in the top of the sidebar; Activity sits at the bottom with Settings.
    static let main: [NavItem] = [.dashboard, .cleanup, .lens, .files, .projects, .apps]

    var symbol: String {
        switch self {
        case .dashboard: return "sparkles.rectangle.stack.fill"
        case .cleanup: return "sparkles"
        case .lens: return "chart.pie.fill"
        case .files: return "doc.fill"
        case .projects: return "hammer.fill"
        case .apps: return "square.grid.2x2.fill"
        case .activity: return "chart.line.uptrend.xyaxis"
        }
    }

    /// 3D icon in Resources/Art.
    var icon: String {
        switch self {
        case .dashboard: return "icon-smartcare"
        case .cleanup: return "icon-cleanup"
        case .lens: return "icon-lens"
        case .files: return "icon-files"
        case .projects: return "icon-projects"
        case .apps: return "icon-apps"
        case .activity: return "icon-activity"
        }
    }

    var color: Color {
        switch self {
        case .dashboard: return Color(0.45, 0.55, 1.0)
        case .cleanup: return Color(0.25, 0.85, 0.6)
        case .lens: return Color(0.4, 0.7, 1.0)
        case .files: return Color(1.0, 0.45, 0.75)
        case .projects: return Color(1.0, 0.7, 0.3)
        case .apps: return Color(0.7, 0.55, 1.0)
        case .activity: return Color(0.4, 0.8, 1.0)
        }
    }

    /// Each section has its own background, like CleanMyMac's modules.
    var gradient: (top: Color, bottom: Color, glow: Color) {
        switch self {
        case .dashboard: return (Color(0.22, 0.30, 0.92), Color(0.16, 0.10, 0.52), Color(0.55, 0.45, 1.0))
        case .cleanup: return (Color(0.06, 0.48, 0.36), Color(0.02, 0.17, 0.15), Color(0.35, 0.95, 0.65))
        case .lens: return (Color(0.10, 0.36, 0.80), Color(0.03, 0.10, 0.30), Color(0.40, 0.75, 1.0))
        case .files: return (Color(0.58, 0.12, 0.44), Color(0.20, 0.03, 0.20), Color(1.0, 0.45, 0.75))
        case .projects: return (Color(0.62, 0.34, 0.08), Color(0.22, 0.09, 0.03), Color(1.0, 0.70, 0.30))
        case .apps: return (Color(0.40, 0.17, 0.72), Color(0.13, 0.05, 0.31), Color(0.70, 0.50, 1.0))
        case .activity: return (Color(0.08, 0.38, 0.62), Color(0.03, 0.10, 0.22), Color(0.40, 0.80, 1.0))
        }
    }

    /// Cmd+1 to Cmd+7.
    var shortcut: Character { Character("\((NavItem.allCases.firstIndex(of: self) ?? 0) + 1)") }
}

/// The background of a section: its gradient with a soft glow near the top right.
struct SectionBackdrop: View {
    let section: NavItem

    var body: some View {
        let colors = section.gradient
        ZStack {
            LinearGradient(colors: [colors.top, colors.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [colors.glow.opacity(0.42), .clear], center: UnitPoint(x: 0.75, y: 0.12),
                           startRadius: 0, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

/// The background used outside the main window's sections (onboarding, Settings).
struct WindowBackdrop: View {
    var glow = false

    var body: some View { SectionBackdrop(section: .dashboard) }
}

/// Stand-in for the real window buttons in off-screen renders.
struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
        }
        .frame(width: 52, height: 12)
    }
}

/// The app's mark: a glowing tick ring on a navy rounded square, like the app icon.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.17, blue: 0.36), Color(red: 0.02, green: 0.05, blue: 0.14)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                TickRing(progress: 0.72, colors: (Theme.cyan, Theme.green), ticks: size > 60 ? 48 : 28,
                         tickLength: size * 0.1, tickWidth: max(size * 0.035, 1.2))
                    .padding(size * 0.16))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .frame(width: size, height: size)
            .shadow(color: Theme.cyan.opacity(0.25), radius: size * 0.15, y: size * 0.05)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
        }
    }
}

/// A window page: title and subtitle with actions on the right, content below.
struct WindowPage<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 10) {
                PageHeader(title: title, subtitle: subtitle)
                Spacer(minLength: 12)
                trailing()
            }
            content()
        }
        .padding(.horizontal, 30)
        .padding(.top, 62)
        .padding(.bottom, 26)
    }
}

extension View {
    /// A list page from the panel, shown as a card in the window.
    func windowCard() -> some View {
        self
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
    }
}

extension AppModel {
    var scannedLine: String {
        guard let scan else { return scanning ? "Scanning your home folder..." : "Not scanned yet" }
        return "Scanned \(PanelView.relative(scan.date))"
    }
}

/// The main action: a cyan capsule with a soft glow that lifts on hover.
struct GlowButtonStyle: ButtonStyle {
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        GlowBody(configuration: configuration, large: large)
    }

    private struct GlowBody: View {
        let configuration: Configuration
        let large: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: large ? 15 : 12.5, weight: .semibold))
                .foregroundStyle(Theme.onCyan)
                .padding(.horizontal, large ? 36 : 16)
                .padding(.vertical, large ? 13 : 8)
                .background(Capsule().fill(LinearGradient(colors: [Theme.cyan, Theme.cyan.opacity(0.8)],
                                                          startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(hovering ? 0.35 : 0.15)))
                .shadow(color: Theme.cyan.opacity(enabled ? (hovering ? 0.6 : 0.4) : 0), radius: large ? (hovering ? 22 : 16) : 8, y: 4)
                .scaleEffect(configuration.isPressed ? 0.97 : hovering ? 1.03 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}
