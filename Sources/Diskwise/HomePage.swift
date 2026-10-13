import SwiftUI
import DiskwiseCore

/// Overview: how full the disk is and what fills it, one-click cleanup, the
/// tools, and available space over the last week.
struct HomePage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            overview
            if !model.fullDiskAccess { accessBanner }
            cleanupCard
            tools
            historyCard
        }
        .padding(14)
    }

    // MARK: Overview

    private var level: SpaceLevel { SpaceLevel(available: model.disk?.available ?? .max) }

    private var overview: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                TickRing(progress: model.disk?.usedFraction ?? 0, colors: level.ringColors,
                         ticks: 56, tickLength: 9, tickWidth: 3)
                VStack(spacing: 0) {
                    Text("\(model.disk?.usedPercent ?? 0)%").font(Theme.number(22)).foregroundStyle(Theme.text)
                    Text("used").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 7) {
                if let disk = model.disk {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Bytes.format(disk.available)).font(Theme.number(26)).foregroundStyle(level == .fine ? Theme.text : level.color)
                        Text("available").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                    }
                    Text(capacityLine(disk)).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    DiskBar(parts: model.breakdown, total: disk.total).padding(.top, 2)
                    legend
                }
            }
        }
        .padding(14)
        .card()
    }

    private func capacityLine(_ disk: DiskInfo) -> String {
        var line = "\(Bytes.format(disk.used)) used of \(Bytes.format(disk.total))"
        if disk.purgeable > Bytes.gb { line += ", \(Bytes.format(disk.purgeable)) purgeable" }
        return line
    }

    private var legend: some View {
        let parts = model.breakdown.filter { $0.1 > 0 }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading), count: 3),
                         alignment: .leading, spacing: 4) {
            ForEach(parts, id: \.0) { category, size in
                HStack(spacing: 4) {
                    Circle().fill(category.color).frame(width: 6, height: 6)
                    Text(category.rawValue).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(Bytes.format(size)).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
        }
    }

    private var accessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.amber)
            Text("Give Diskwise Full Disk Access to also check the Trash, Mail and app containers.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 6)
            Button("Open Settings") { model.openFullDiskAccessSettings() }.buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .card(radius: 10, fill: Theme.amber.opacity(0.08))
    }

    // MARK: Cleanup

    private var cleanupCard: some View {
        let selected = model.selectedBytes
        let more = max(model.cleanupTotal - selected, 0)
        return HStack(spacing: 12) {
            IconChip(symbol: "sparkles", color: Theme.cyan, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                if model.groups.isEmpty, model.cleanupLoading {
                    Text("Looking for junk...").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                } else {
                    HStack(spacing: 6) {
                        Text("\(Bytes.format(selected)) ready to clean").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if model.cleanupMeasuring { Spinner(size: 10) }
                    }
                }
                Text(more > Bytes.gb ? "Caches, logs and build data. \(Bytes.format(more)) more you can review."
                     : "Caches, logs and build data that apps rebuild on their own.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("Review") { model.page = .cleanup }.buttonStyle(PillButtonStyle())
            Button("Clean") { model.confirmClean() }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(selected == 0 || model.busy != nil)
        }
        .padding(12)
        .card()
    }

    // MARK: Tools

    private var tools: some View {
        let large = model.largeFiles.reduce(0) { $0 + $1.size } + model.downloads.reduce(0) { $0 + $1.size }
        let stale = model.staleProjects
        let unused = model.apps.filter { app in app.lastUsed.map { Date().timeIntervalSince($0) > 90 * 86_400 } ?? true }
        let scanning = model.scan == nil
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ToolTile(symbol: "folder.fill", color: Theme.blue, title: "Explore disk",
                     value: model.scan.map { Bytes.format($0.root.size) } ?? "...",
                     detail: scanning ? "Scanning your home folder" : "in your home folder") { model.page = .explore([]) }
            ToolTile(symbol: "doc.fill", color: Theme.pink, title: "Large and old files",
                     value: scanning ? "..." : Bytes.format(large),
                     detail: scanning ? "Waiting for the scan"
                         : "\(model.largeFiles.count) big files, \(model.downloads.count) old downloads") { model.page = .files }
            ToolTile(symbol: "hammer.fill", color: Theme.amber, title: "Project junk",
                     value: scanning ? "..." : Bytes.format(stale.reduce(0) { $0 + $1.size }),
                     detail: scanning ? "Waiting for the scan"
                         : "\(stale.count) folders untouched 30+ days") { model.page = .projects }
            ToolTile(symbol: "square.grid.2x2.fill", color: Theme.violet, title: "Apps",
                     value: model.apps.isEmpty ? "..." : "\(model.apps.count) apps",
                     detail: unused.isEmpty ? "Uninstall with leftovers" : "\(unused.count) unused for 3 months") { model.page = .apps }
        }
    }

    // MARK: History

    private var historyCard: some View {
        let points = model.history.recent(days: 7)
        let change = model.history.change(days: 7)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Available space", detail: "last 7 days")
                Spacer()
                if let change, abs(change) >= 100 * Bytes.mb {
                    Text("\(change < 0 ? "-" : "+")\(Bytes.format(abs(change)))")
                        .font(Theme.number(11, .semibold))
                        .foregroundStyle(change < 0 ? Theme.amber : Theme.green)
                }
            }
            if points.count >= 2 {
                AreaChart(values: points.map { Double($0.available) }, color: level == .fine ? Theme.cyan : level.color)
            } else {
                Text("Collecting data. The chart fills in over the next few hours.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            }
            HStack(spacing: 6) {
                Image(systemName: model.alertsOn ? "bell.fill" : "bell.slash").font(.system(size: 10))
                    .foregroundStyle(model.alertsOn ? Theme.cyan : Theme.tertiary)
                Text(model.alertsOn ? "Notifies you when less than 10 GB is left" : "Low space alerts are off")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                Spacer()
                Button(model.alertsOn ? "Turn off" : "Turn on") { model.alertsOn.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
            }
        }
        .padding(12)
        .card()
    }
}

struct ToolTile: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconChip(symbol: symbol, color: color, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                    Text(value).font(Theme.number(16)).foregroundStyle(Theme.text)
                    Text(detail).font(.system(size: 10)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
            }
            .padding(10)
            .card(fill: hovering ? Color.white.opacity(0.1) : Theme.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
