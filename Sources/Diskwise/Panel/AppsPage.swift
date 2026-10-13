import SwiftUI
import DiskwiseCore

/// Installed apps by size or last use; click one to uninstall it.
struct AppsPage: View {
    @ObservedObject var model: AppModel
    var live: Bool
    var listHeight: CGFloat? = 400
    /// The window shows the detail itself; the panel navigates.
    var onOpen: ((InstalledApp) -> Void)? = nil
    @State private var order = Order.size

    enum Order: Hashable { case size, lastUsed, name }

    private var sorted: [InstalledApp] {
        switch order {
        case .size: return model.apps.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .lastUsed: return model.apps.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        case .name: return model.apps
        }
    }

    var body: some View {
        let apps = sorted
        let biggest = apps.compactMap(\.size).max() ?? 1
        return VStack(spacing: 0) {
            PageToolbar {
                SegmentedTabs(items: [(Order.size, "Size"), (Order.lastUsed, "Least used"), (Order.name, "Name")],
                              selection: $order)
                    .fixedSize()
                Spacer()
                Text("\(apps.count) apps, \(Bytes.format(apps.compactMap(\.size).reduce(0, +)))")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            ListArea(live: live, height: listHeight) {
                ForEach(apps) { app in
                    ListRow(icon: { FileIcon(path: app.path, size: 26) },
                            title: app.name,
                            badge: app.version.isEmpty ? nil : app.version,
                            subtitle: app.lastUsed.map { "Opened \(ageText($0))" } ?? "Never opened",
                            size: app.size,
                            fraction: app.size.map { Double($0) / Double(max(biggest, 1)) },
                            onOpen: { if let onOpen { onOpen(app) } else { model.openApp(app) } })
                }
            }
            .padding(.horizontal, 6)
            PageFooter(note: "Apple's own apps aren't listed. Uninstalled apps go to the Trash.") { EmptyView() }
        }
    }
}

/// One app with the support files, caches and preferences it leaves behind.
struct AppDetailPage: View {
    @ObservedObject var model: AppModel
    let path: String
    var live: Bool
    var listHeight: CGFloat? = 280

    var body: some View {
        if let app = model.apps.first(where: { $0.path == path }) {
            content(app)
        } else {
            EmptyNote(symbol: "questionmark.app", title: "App not found").frame(height: 300)
        }
    }

    private func content(_ app: InstalledApp) -> some View {
        let chosen = model.leftovers.filter { model.leftoverSelection.contains($0.path) }
        let total = (app.size ?? 0) + chosen.reduce(0) { $0 + ($1.size ?? 0) }
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                FileIcon(path: app.path, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    Text([app.version.isEmpty ? nil : "Version \(app.version)", app.bundleID].compactMap { $0 }.joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Text(app.lastUsed.map { "Last opened \(ageText($0))" } ?? "Never opened")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(app.size.map(Bytes.format) ?? "...").font(Theme.number(18)).foregroundStyle(Theme.text)
                    Text("app size").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(14)
            Hairline()
            PageToolbar {
                SectionLabel(text: "Related files", detail: model.leftoversLoading ? nil : "\(model.leftovers.count) found")
                if model.leftoversLoading { Spinner(size: 10) }
                Spacer()
            }
            ListArea(live: live, height: listHeight) {
                if !model.leftoversLoading && model.leftovers.isEmpty {
                    EmptyNote(symbol: "checkmark.seal", title: "No leftovers found", detail: "Only the app itself will be removed.")
                }
                ForEach(model.leftovers) { item in
                    ListRow(checked: model.leftoverSelection.contains(item.path),
                            toggle: { toggle(item.path) },
                            icon: { FileIcon(path: item.path, size: 18) },
                            title: item.name,
                            subtitle: item.kind,
                            size: item.size,
                            actions: [RowAction(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(item.path) }])
                }
            }
            .padding(.horizontal, 6)
            PageFooter(note: "Everything goes to the Trash, so you can still put it back.") {
                Button("Show in Finder") { model.reveal(app.path) }.buttonStyle(PillButtonStyle())
                Button("Uninstall \(Bytes.format(total))") { model.confirmUninstall(app) }
                    .buttonStyle(PillButtonStyle(destructive: true))
                    .disabled(model.leftoversLoading || model.busy != nil)
            }
        }
    }

    private func toggle(_ path: String) {
        if model.leftoverSelection.contains(path) { model.leftoverSelection.remove(path) } else { model.leftoverSelection.insert(path) }
    }
}
