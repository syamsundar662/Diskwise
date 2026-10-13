import SwiftUI
import DiskwiseCore

/// Big files anywhere in your folders, and downloads you haven't opened in months.
struct FilesPage: View {
    @ObservedObject var model: AppModel
    var live: Bool
    var listHeight: CGFloat? = 380
    @State private var tab = Tab.large
    @State private var minimum: Int64 = 100 * Bytes.mb

    enum Tab: Hashable { case large, downloads }

    private struct Row: Identifiable {
        let path: String
        let size: Int64
        let detail: String
        var id: String { path }
    }

    private var rows: [Row] {
        switch tab {
        case .large:
            return model.largeFiles.filter { $0.size >= minimum }.map { file in
                Row(path: file.path, size: file.size,
                    detail: "\(shortPath((file.path as NSString).deletingLastPathComponent)), changed \(ageText(file.modified))")
            }
        case .downloads:
            return model.downloads.map { item in
                Row(path: item.path, size: item.size,
                    detail: "Added \(ageText(item.added)), opened \(ageText(item.lastOpened))")
            }
        }
    }

    var body: some View {
        let rows = rows
        let chosen = rows.filter { model.fileSelection.contains($0.path) }
        let chosenSize = chosen.reduce(0) { $0 + $1.size }
        let biggest = rows.map(\.size).max() ?? 1
        return VStack(spacing: 0) {
            PageToolbar {
                SegmentedTabs(items: [(Tab.large, "Large files"), (Tab.downloads, "Old downloads")], selection: $tab)
                    .fixedSize()
                Spacer()
                if tab == .large {
                    SegmentedTabs(items: [(100 * Bytes.mb, "100 MB+"), (500 * Bytes.mb, "500 MB+"), (Bytes.gb, "1 GB+")],
                                  selection: $minimum)
                        .fixedSize()
                } else {
                    Text("Not opened in \(Downloads.oldDays) days").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            ListArea(live: live, height: listHeight) {
                if model.scan == nil {
                    EmptyNote(symbol: "magnifyingglass", title: "Waiting for the scan...",
                              detail: "Big files show up here once your home folder has been scanned.")
                } else if rows.isEmpty {
                    EmptyNote(symbol: "checkmark.seal",
                              title: tab == .large ? "No files over \(Bytes.format(minimum))" : "No old downloads",
                              detail: tab == .large ? "Dependencies, caches and app data are left out of this list." : nil)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    ListRow(checked: model.fileSelection.contains(row.path),
                            toggle: { toggle(row.path) },
                            icon: { FileIcon(path: row.path, size: 22) },
                            title: (row.path as NSString).lastPathComponent,
                            safety: SafetyAdvisor.verdict(for: row.path),
                            subtitle: row.detail,
                            size: row.size,
                            fraction: Double(row.size) / Double(max(biggest, 1)),
                            actions: [RowAction(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(row.path) }])
                        .staggered(index)
                        .rowRemoval()
                }
                .animation(.easeInOut(duration: 0.35), value: rows.map(\.id))
            }
            .padding(.horizontal, 6)
            PageFooter(note: chosen.isEmpty ? "Select files to move them to the Trash." : "\(chosen.count) selected, \(Bytes.format(chosenSize))") {
                Button("Move to Trash") { model.confirmTrash(chosen.map(\.path), sizes: chosen.map(\.size)) }
                    .buttonStyle(PillButtonStyle(destructive: true))
                    .disabled(chosen.isEmpty || model.busy != nil)
            }
        }
    }

    private func toggle(_ path: String) {
        if model.fileSelection.contains(path) { model.fileSelection.remove(path) } else { model.fileSelection.insert(path) }
    }
}

/// node_modules, build and similar folders, newest-untouched first.
struct ProjectsPage: View {
    @ObservedObject var model: AppModel
    var live: Bool
    var listHeight: CGFloat? = 380
    @State private var staleOnly = true

    var body: some View {
        let rows = staleOnly ? model.staleProjects : model.projects
        let chosen = model.projects.filter { model.projectSelection.contains($0.path) }
        let chosenSize = chosen.reduce(0) { $0 + $1.size }
        let biggest = rows.map(\.size).max() ?? 1
        return VStack(spacing: 0) {
            PageToolbar {
                SegmentedTabs(items: [(true, "Untouched 30+ days"), (false, "All projects")], selection: $staleOnly)
                    .fixedSize()
                Spacer()
                Text("\(rows.count) folders, \(Bytes.format(rows.reduce(0) { $0 + $1.size }))")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            ListArea(live: live, height: listHeight) {
                if model.scan == nil {
                    EmptyNote(symbol: "magnifyingglass", title: "Waiting for the scan...")
                } else if rows.isEmpty {
                    EmptyNote(symbol: "checkmark.seal", title: staleOnly ? "No idle projects" : "No project folders found",
                              detail: "Looks for node_modules, build, Pods, target, .next, .venv and similar folders.")
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    ListRow(checked: model.projectSelection.contains(item.path),
                            toggle: { toggle(item.path) },
                            icon: { FileIcon(path: item.project, size: 22) },
                            title: item.projectName,
                            badge: item.name,
                            safety: SafetyAdvisor.verdict(for: item.path),
                            subtitle: "\(shortPath(item.project)), touched \(ageText(item.lastTouched))",
                            size: item.size,
                            fraction: Double(item.size) / Double(max(biggest, 1)),
                            actions: [RowAction(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(item.path) }])
                        .staggered(index)
                        .rowRemoval()
                }
                .animation(.easeInOut(duration: 0.35), value: rows.map(\.id))
            }
            .padding(.horizontal, 6)
            PageFooter(note: "Deleted for good. Rebuild with npm install,\npod install or your build tool.") {
                Button(chosen.isEmpty ? "Delete" : "Delete \(Bytes.format(chosenSize))") { model.confirmDeleteProjects() }
                    .buttonStyle(PillButtonStyle(destructive: true))
                    .disabled(chosen.isEmpty || model.busy != nil)
            }
        }
    }

    private func toggle(_ path: String) {
        if model.projectSelection.contains(path) { model.projectSelection.remove(path) } else { model.projectSelection.insert(path) }
    }
}
