import SwiftUI
import DiskwiseCore

/// The home folder as a size-sorted tree from the last scan: click a folder to
/// go in, reveal or trash anything you don't need.
struct ExplorePage: View {
    @ObservedObject var model: AppModel
    let parts: [String]
    var live: Bool

    private var home: String { NSHomeDirectory() }
    private func path(_ components: [String]) -> String { ([home] + components).joined(separator: "/") }

    var body: some View {
        VStack(spacing: 0) {
            PageToolbar { breadcrumb }
            if let node = model.scan?.root.node(at: parts.joined(separator: "/")) {
                ListArea(live: live, height: 400) {
                    ForEach(node.children) { child in row(child, parent: node) }
                    if node.restCount > 0 {
                        ListRow(icon: { IconChip(symbol: "ellipsis", color: Theme.gray, size: 20) },
                                title: "\(node.restCount) smaller items", subtitle: "Each under \(Bytes.format(20 * Bytes.mb))",
                                size: node.restSize, fraction: Double(node.restSize) / Double(max(node.size, 1)))
                    }
                    if node.children.isEmpty && node.restCount == 0 {
                        EmptyNote(symbol: "folder", title: "Empty folder")
                    }
                }
                .padding(.horizontal, 6)
            } else if model.scanning || model.scan == nil {
                ListArea(live: live, height: 400) {
                    EmptyNote(symbol: "magnifyingglass", title: "Scanning your home folder...",
                              detail: model.scanProgress.map { "\(Bytes.format($0.bytes)) checked so far. This takes a few minutes the first time." }
                                ?? "This takes a few minutes the first time.")
                }
            } else {
                ListArea(live: live, height: 400) {
                    EmptyNote(symbol: "questionmark.folder", title: "This folder is gone", detail: "Rescan to update the list.")
                }
            }
            PageFooter(note: footnote) {
                Button(model.scanning ? "Stop scan" : "Rescan") {
                    if model.scanning { model.stopScan() } else { model.startScan() }
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }

    private var footnote: String {
        guard let scan = model.scan else { return "Removed items go to the Trash." }
        var note = "Sizes from the scan \(PanelView.relative(scan.date)). Removed items go to the Trash."
        if !model.fullDiskAccess { note += "\nApp containers and Mail need Full Disk Access." }
        return note
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            crumb("Home", depth: 0)
            ForEach(Array(parts.enumerated()), id: \.offset) { i, name in
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.tertiary)
                crumb(name, depth: i + 1)
            }
            Spacer()
            if let node = model.scan?.root.node(at: parts.joined(separator: "/")) {
                Text(Bytes.format(node.size)).font(Theme.number(12, .semibold)).foregroundStyle(Theme.text)
            }
        }
    }

    private func crumb(_ name: String, depth: Int) -> some View {
        let current = depth == parts.count
        return Button(name) { model.page = .explore(Array(parts.prefix(depth))) }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: current ? .semibold : .medium))
            .foregroundStyle(current ? Theme.text : Theme.cyan)
            .lineLimit(1)
            .disabled(current)
    }

    private func row(_ child: FolderNode, parent: FolderNode) -> some View {
        let childParts = parts + [child.name]
        let full = path(childParts)
        let verdict = SafetyAdvisor.verdict(for: full)
        var actions = [RowAction(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(full) }]
        if SafeDelete.refusal(for: full) == nil, verdict.safety != .unsafe {
            actions.append(RowAction(symbol: "trash", help: "Move to Trash", destructive: true) {
                model.confirmTrash([full], sizes: [child.size])
            })
        }
        let canOpen = child.isDirectory && (!child.children.isEmpty || child.restCount > 0)
        return ListRow(icon: { FileIcon(path: full, size: 20) },
                       title: child.name,
                       safety: verdict,
                       subtitle: child.isDirectory ? itemsText(child) : "File",
                       size: child.size,
                       fraction: Double(child.size) / Double(max(parent.size, 1)),
                       actions: actions,
                       onOpen: canOpen ? { model.page = .explore(childParts) } : nil)
    }

    private func itemsText(_ node: FolderNode) -> String {
        let count = node.children.count + node.restCount
        return count == 1 ? "1 item" : "\(count) items"
    }
}
