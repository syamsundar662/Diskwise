import SwiftUI
import DiskwiseCore

/// The panel: a header, the current page, and overlays for the menu,
/// confirmations, progress and results. Shown in a FloatingPanel.
struct PanelView: View {
    @ObservedObject var model: AppModel
    /// Off for snapshots: off-screen renders can't scroll or blur the desktop.
    var live = true
    var onSize: ((CGSize) -> Void)? = nil
    @State private var showingMenu = false

    static let width: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            page
        }
        .frame(width: Self.width)
        .glassPanel(live: live)
        .overlay(alignment: .bottom) { StatusOverlay(model: model) }
        .overlay(alignment: .topTrailing) { if showingMenu { menu } }
        .overlay { if let confirmation = model.confirmation { ConfirmCard(confirmation: confirmation, model: model) } }
        .environment(\.colorScheme, .dark)
        .fixedSize()
        .background(GeometryReader { Color.clear.preference(key: PanelSizeKey.self, value: $0.size) })
        .onPreferenceChange(PanelSizeKey.self) { onSize?($0) }
    }

    @ViewBuilder
    private var page: some View {
        switch model.page {
        case .home: HomePage(model: model)
        case .cleanup: CleanupPage(model: model, live: live)
        case .explore(let parts): ExplorePage(model: model, parts: parts, live: live)
        case .files: FilesPage(model: model, live: live)
        case .projects: ProjectsPage(model: model, live: live)
        case .apps: AppsPage(model: model, live: live)
        case .app(let path): AppDetailPage(model: model, path: path, live: live)
        }
    }

    private var title: String {
        switch model.page {
        case .home: return model.disk?.name ?? "Macintosh HD"
        case .cleanup: return "Cleanup"
        case .explore(let parts): return parts.last ?? "Home folder"
        case .files: return "Large and old files"
        case .projects: return "Project junk"
        case .apps: return "Apps"
        case .app(let path): return model.apps.first { $0.path == path }?.name ?? "App"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if model.page == .home {
                IconChip(symbol: "internaldrive.fill", color: Theme.cyan, size: 28)
            } else {
                IconButton(symbol: "chevron.left", size: 26) { withAnimation(.easeOut(duration: 0.15)) { model.back() } }
                    .help("Back")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                statusLine
            }
            Spacer()
            if model.page == .home {
                IconButton(symbol: "arrow.clockwise") { model.refreshAll() }.help("Refresh and rescan")
            }
            IconButton(symbol: "macwindow") {
                NSApp.sendAction(#selector(AppDelegate.showMainWindow(_:)), to: nil, from: nil)
            }
            .help("Open Diskwise")
            IconButton(symbol: "ellipsis") { withAnimation(.easeOut(duration: 0.15)) { showingMenu.toggle() } }
                .help("More")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 5) {
            if model.scanning {
                Spinner(size: 9)
                let progress = model.scanProgress
                Text(progress.map { "Scanning \($0.current.isEmpty ? "home folder" : $0.current)... \(Bytes.format($0.bytes)) checked" }
                     ?? "Starting scan...")
            } else if model.cleanupMeasuring {
                Spinner(size: 9)
                Text("Measuring caches...")
            } else if let scan = model.scan {
                Text("Scanned \(Self.relative(scan.date))")
            } else {
                Text("Not scanned yet")
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Theme.secondary)
        .lineLimit(1)
    }

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Dropdown under the "more" button; a click anywhere else closes it.
    private var menu: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { showingMenu = false } }
            VStack(alignment: .leading, spacing: 2) {
                MenuRow(symbol: "arrow.triangle.2.circlepath", title: model.scanning ? "Scanning..." : "Rescan disk") {
                    showingMenu = false
                    model.startScan()
                }
                MenuRow(symbol: model.alertsOn ? "checkmark.circle.fill" : "circle", title: "Alert when under \(Preferences.shared.alertThresholdGB) GB") {
                    showingMenu = false
                    model.alertsOn.toggle()
                }
                if !model.fullDiskAccess {
                    MenuRow(symbol: "lock.open", title: "Grant Full Disk Access...") {
                        showingMenu = false
                        model.openFullDiskAccessSettings()
                    }
                }
                MenuRow(symbol: "gearshape", title: "Open Storage settings") {
                    showingMenu = false
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!)
                }
                Hairline().padding(.vertical, 3)
                MenuRow(symbol: "macwindow", title: "Open Diskwise") {
                    showingMenu = false
                    NSApp.sendAction(#selector(AppDelegate.showMainWindow(_:)), to: nil, from: nil)
                }
                MenuRow(symbol: "gearshape", title: "Settings...") {
                    showingMenu = false
                    NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
                }
                MenuRow(symbol: "power", title: "Quit Diskwise") { NSApp.terminate(nil) }
            }
            .padding(5)
            .frame(width: 230)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            .padding(.trailing, 12)
            .padding(.top, 46)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
        }
    }
}

/// Progress while something runs, then the result for a few seconds.
struct StatusOverlay: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack { content }
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.toast)
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.busy)
    }

    @ViewBuilder
    private var content: some View {
        if let busy = model.busy {
            HStack(spacing: 8) {
                Spinner(size: 12)
                Text(busy).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.raised))
            .overlay(Capsule().strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let toast = model.toast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                Text(toast.text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if toast.emptyTrash {
                    Button("Empty Trash") { model.confirmEmptyTrash() }.buttonStyle(PillButtonStyle())
                }
                Button { model.toast = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 500)
            .background(Capsule().fill(Theme.raised))
            .overlay(Capsule().strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Dims the panel and asks before anything is removed.
struct ConfirmCard: View {
    let confirmation: Confirmation
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .onTapGesture { model.confirmation = nil }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconChip(symbol: "trash.fill", color: Theme.red, size: 30)
                    Text(confirmation.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                }
                Text(confirmation.message).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { model.confirmation = nil }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(confirmation.action) {
                        model.confirmation = nil
                        confirmation.perform()
                    }
                    .buttonStyle(PillButtonStyle(destructive: true))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(width: 360)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Bottom bar of list pages: a note on the left, the main action on the right.
struct PageFooter<Actions: View>: View {
    let note: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                actions()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.shade)
        }
    }
}

/// Bar under the header with filters or a summary.
struct PageToolbar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) { content() }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            Hairline()
        }
    }
}

private struct PanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
