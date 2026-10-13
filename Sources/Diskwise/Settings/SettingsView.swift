import AppKit
import SwiftUI
import DiskwiseCore

/// The Settings window: General, Cleanup, Alerts, Updates and About.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs = Preferences.shared
    @State var tab = Tab.general
    @State private var automaticUpdates = Updater.shared.automaticallyChecks

    enum Tab: String, CaseIterable {
        case general = "General", cleanup = "Cleanup", alerts = "Alerts", updates = "Updates", about = "About"

        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .cleanup: return "sparkles"
            case .alerts: return "bell.fill"
            case .updates: return "arrow.down.circle.fill"
            case .about: return "info.circle.fill"
            }
        }
    }

    static let size = CGSize(width: 600, height: 440)

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Hairline()
            ZStack {
                content.id(tab).transition(.opacity.combined(with: .offset(y: 8)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(24)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(WindowBackdrop())
        .environment(\.colorScheme, .dark)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button { withAnimation(.easeOut(duration: 0.2)) { tab = item } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold))
                        Text(item.rawValue).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(tab == item ? Theme.cyan : Theme.secondary)
                    .frame(width: 76, height: 50)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tab == item ? Theme.cyan.opacity(0.14) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 34)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general:
            section {
                row("power", Theme.green, "Open at login", "Keeps the menu bar item and alerts running.") {
                    PillToggle(isOn: $prefs.launchAtLogin)
                }
                Hairline()
                row("menubar.rectangle", Theme.cyan, "Show in the menu bar", "Disk usage at a glance, with quick cleanup.") {
                    PillToggle(isOn: $prefs.showMenuBarItem)
                }
                Hairline()
                row("lock.shield.fill", Theme.amber, "Full Disk Access",
                    model.fullDiskAccess ? "Granted. Diskwise can measure everything." : "Needed for the Trash, Mail and app containers.") {
                    if model.fullDiskAccess {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.system(size: 16))
                    } else {
                        Button("Open Settings") { model.openFullDiskAccessSettings() }.buttonStyle(PillButtonStyle())
                    }
                }
            }
        case .cleanup:
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Folders Diskwise never touches").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Nothing inside these folders is listed or removed, by any tool.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
                VStack(spacing: 0) {
                    if prefs.excludedPaths.isEmpty {
                        Text("No excluded folders").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(prefs.excludedPaths, id: \.self) { path in
                                ListRow(icon: { FileIcon(path: path, size: 18) }, title: (path as NSString).lastPathComponent,
                                        subtitle: shortPath(path), size: nil, showsSize: false,
                                        actions: [RowAction(symbol: "minus", help: "Remove", destructive: true) {
                                            prefs.excludedPaths.removeAll { $0 == path }
                                            model.exclusionsChanged()
                                        }])
                            }
                        }
                    }
                    .frame(maxHeight: prefs.excludedPaths.isEmpty ? 0 : 200)
                }
                .card(radius: 12)
                Button { addExcludedFolder() } label: { Label("Add Folder...", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle())
            }
        case .alerts:
            section {
                row("bell.fill", Theme.amber, "Warn me when space runs low", "Sends one notification when you drop under the limit.") {
                    PillToggle(isOn: $model.alertsOn)
                }
                Hairline()
                row("gauge.with.dots.needle.33percent", Theme.cyan, "Limit", "Alert when available space drops under this.") {
                    SegmentedTabs(items: [(5, "5 GB"), (10, "10 GB"), (20, "20 GB"), (30, "30 GB")], selection: $prefs.alertThresholdGB)
                        .fixedSize()
                }
                Hairline()
                row("paperplane.fill", Theme.violet, "Test notification", "Check that notifications reach you.") {
                    Button("Send") { if let disk = model.disk { Notifier.lowSpace(disk) } }.buttonStyle(PillButtonStyle())
                }
            }
        case .updates:
            section {
                row("arrow.down.circle.fill", Theme.cyan, "Check for updates automatically", "Diskwise looks for new versions once a day.") {
                    PillToggle(isOn: Binding(get: { automaticUpdates }, set: { automaticUpdates = $0; Updater.shared.automaticallyChecks = $0 }))
                }
                Hairline()
                row("sparkle.magnifyingglass", Theme.teal, "Version \(Self.version)", "You can also check now.") {
                    Button("Check Now") { Updater.shared.checkForUpdates() }
                        .buttonStyle(PillButtonStyle())
                        .disabled(!Updater.shared.canCheck)
                }
            }
        case .about:
            VStack(spacing: 14) {
                AppMark(size: 84)
                Text("Diskwise").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.text)
                Text("Version \(Self.version)").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Text("See what fills your Mac and free up space, safely.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                Text("Copyright 2026 Syam Sundar").font(.system(size: 11)).foregroundStyle(Theme.tertiary).padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }.card(radius: 14)
    }

    private func row<Accessory: View>(_ symbol: String, _ color: Color, _ title: String, _ detail: String,
                                      @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 14) {
            IconChip(symbol: symbol, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 10)
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func addExcludedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.prompt = "Exclude"
        panel.message = "Diskwise will never list or remove anything inside these folders."
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.map(\.path).filter { !prefs.excludedPaths.contains($0) }
        prefs.excludedPaths += added
        model.exclusionsChanged()
    }
}
