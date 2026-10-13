import SwiftUI
import DiskwiseCore

/// Every cleanup group with a checkbox; expand a group to pick single items.
struct CleanupPage: View {
    @ObservedObject var model: AppModel
    var live: Bool
    var listHeight: CGFloat? = 380
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            PageToolbar {
                Text("\(Bytes.format(model.selectedBytes)) selected")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                Text("of \(Bytes.format(model.cleanupTotal)) found").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                if model.cleanupMeasuring { Spinner(size: 10) }
                Spacer()
                Button("Recommended") { model.resetSelection() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cyan)
                    .help("Select the safe defaults again")
            }
            ListArea(live: live, height: listHeight) {
                if model.groups.isEmpty {
                    if model.cleanupLoading {
                        EmptyNote(symbol: "magnifyingglass", title: "Looking for junk...")
                    } else {
                        EmptyNote(symbol: "checkmark.seal", title: "Nothing to clean", detail: "No caches or logs worth removing right now.")
                    }
                }
                ForEach(model.groups) { group in
                    groupRow(group)
                    if expanded.contains(group.id) {
                        ForEach(group.items.sorted { ($0.size ?? 0) > ($1.size ?? 0) }) { item in itemRow(item) }
                    }
                }
                trashRow
            }
            .padding(.horizontal, 6)
            PageFooter(note: "Caches are deleted for good and rebuilt when needed.\nCaches of open apps are skipped.") {
                Button("Clean \(Bytes.format(model.selectedBytes))") { model.confirmClean() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(model.selectedBytes == 0 || model.busy != nil)
            }
        }
    }

    private func groupRow(_ group: CleanupGroup) -> some View {
        let usable = group.items.filter { $0.inUseBy == nil }
        let chosen = usable.filter(model.isSelected)
        let open = expanded.contains(group.id)
        return HStack(spacing: 9) {
            Checkbox(checked: !usable.isEmpty && chosen.count == usable.count, mixed: !chosen.isEmpty,
                     disabled: usable.isEmpty) { model.toggle(group) }
            IconChip(symbol: group.symbol, color: Theme.cyan, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(group.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("\(group.items.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.tertiary)
                }
                Text(group.detail).font(.system(size: 10.5)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if group.measuring && group.size == 0 {
                Spinner(size: 11)
            } else {
                Text(Bytes.format(group.size)).font(Theme.number(12.5, .semibold)).foregroundStyle(Theme.text).monospacedDigit()
            }
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                if open { expanded.remove(group.id) } else { expanded.insert(group.id) }
            }
        }
    }

    private func itemRow(_ item: CleanupItem) -> some View {
        ListRow(checked: model.isSelected(item), toggle: { model.toggle(item) }, checkDisabled: item.inUseBy != nil,
                icon: { FileIcon(path: item.path, size: 18) },
                title: item.name,
                subtitle: item.source == item.name ? shortPath(item.path) : item.source,
                warning: item.inUseBy.map { "\($0) is open. Quit it to clean this." },
                size: item.size,
                actions: [RowAction(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(item.path) }])
            .padding(.leading, 26)
    }

    @ViewBuilder
    private var trashRow: some View {
        if model.trashSize.map({ $0 > 0 }) ?? true {
            HStack(spacing: 9) {
                Color.clear.frame(width: 16, height: 16)
                IconChip(symbol: "trash.fill", color: Theme.gray, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trash").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(model.trashSize == nil ? "Size needs Full Disk Access" : "Files you already deleted")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                if let size = model.trashSize {
                    Text(Bytes.format(size)).font(Theme.number(12.5, .semibold)).foregroundStyle(Theme.text)
                }
                Button("Empty") { model.confirmEmptyTrash() }.buttonStyle(PillButtonStyle()).disabled(model.busy != nil)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }
}
