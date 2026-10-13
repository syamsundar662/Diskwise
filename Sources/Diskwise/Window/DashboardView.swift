import SwiftUI
import DiskwiseCore

/// The "Focus" dashboard: one big ring for the disk, one Clean button, and
/// chips that lead to the other tools.
struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var appeared = RenderMode.snapshot

    private var level: SpaceLevel { SpaceLevel(available: model.disk?.available ?? .max) }

    private var headline: String {
        guard let disk = model.disk else { return "Diskwise" }
        switch level {
        case .fine: return "Your disk is in good shape"
        case .low: return "Your disk is \(disk.usedPercent)% full"
        case .critical: return "Your disk is almost full"
        }
    }

    private var subline: String {
        if model.groups.isEmpty && model.cleanupLoading { return "Looking for files you can safely remove..." }
        let bytes = model.selectedBytes
        return bytes > 0 ? "Diskwise found \(Bytes.format(bytes)) you can safely remove."
            : "Nothing to clean right now. Nice and tidy."
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            VStack(spacing: 7) {
                Text(headline).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                Text(subline).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    .contentTransition(.numericText())
            }
            .animation(.easeOut(duration: 0.3), value: headline)
            .animation(.easeOut(duration: 0.3), value: subline)
            ring
            VStack(spacing: 12) {
                Button { model.confirmClean() } label: {
                    Text(model.selectedBytes > 0 ? "Clean \(Bytes.format(model.selectedBytes))" : "Clean")
                        .contentTransition(.numericText())
                }
                .buttonStyle(GlowButtonStyle(large: true))
                .disabled(model.selectedBytes == 0 || model.busy != nil)
                .keyboardShortcut(.return, modifiers: .command)
                Button("Review details") { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { model.section = .cleanup } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
            }
            chips
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .onAppear { withAnimation(.easeOut(duration: 1.3).delay(0.15)) { appeared = true } }
    }

    private var ring: some View {
        ZStack {
            TickRing(progress: appeared ? (model.disk?.usedFraction ?? 0) : 0, colors: level.ringColors,
                     ticks: 90, tickLength: 21, tickWidth: 3.6)
            if model.scanning {
                ScanSweep(ticks: 90, tickLength: 21, tickWidth: 3.6).transition(.opacity)
            }
            VStack(spacing: 4) {
                if let disk = model.disk {
                    RollingBytes(bytes: appeared ? disk.available : 0, font: Theme.number(44))
                    Text("available of \(Bytes.format(disk.total))")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                Group {
                    if model.scanning {
                        HStack(spacing: 5) {
                            Spinner(size: 9)
                            Text(model.scanProgress.map { "Scanning \($0.current.isEmpty ? "home folder" : $0.current)" } ?? "Starting scan")
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.cyan)
                    } else {
                        Text("\(model.disk?.usedPercent ?? 0)% used").foregroundStyle(Theme.tertiary)
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .frame(maxWidth: 190)
                .padding(.top, 4)
            }
        }
        .frame(width: 290, height: 290)
        .animation(.easeOut(duration: 0.4), value: model.scanning)
    }

    private var chips: some View {
        HStack(spacing: 12) {
            ForEach(model.toolValues, id: \.0) { item, value in
                Button { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { model.section = item } } label: {
                    HStack(spacing: 10) {
                        IconChip(symbol: item.symbol, color: item.color, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(value).font(Theme.number(14.5)).foregroundStyle(Theme.text)
                                .contentTransition(.numericText())
                            Text(item.rawValue).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .card(radius: 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverLift()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(model.scannedLine)
            if !model.scanning {
                Text("·")
                Button("Rescan") { model.refreshAll() }.buttonStyle(.plain).foregroundStyle(Theme.cyan)
            }
            if !model.fullDiskAccess {
                Text("·")
                Button("Allow Full Disk Access for complete results") { model.openFullDiskAccessSettings() }
                    .buttonStyle(.plain).foregroundStyle(Theme.amber)
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Theme.tertiary)
    }
}
