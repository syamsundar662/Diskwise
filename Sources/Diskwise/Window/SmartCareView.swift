import SwiftUI
import DiskwiseCore

/// The dashboard: the 3D disc, what Smart Care looks at, and one round button
/// that goes Scan, then progress, then Clean.
struct SmartCareView: View {
    @ObservedObject var model: AppModel
    @State private var shown = RenderMode.snapshot

    private let tint = Color(0.40, 0.45, 1.0)

    private var phase: AppModel.SmartPhase { model.smartPhase }

    private var title: String {
        switch phase {
        case .idle: return "Smart Care"
        case .scanning: return "Scanning your Mac"
        case .done: return model.selectedBytes > 0 ? "Scan complete" : "All clean"
        }
    }

    private var subtitle: String {
        switch phase {
        case .idle:
            return "One scan finds junk, forgotten big files and idle project folders."
        case .scanning:
            if model.scanning, let progress = model.scanProgress {
                return "Looking through \(progress.current.isEmpty ? "your home folder" : progress.current), \(Bytes.format(progress.bytes)) so far."
            }
            return "Measuring caches, logs and build data."
        case .done:
            return model.selectedBytes > 0
                ? "\(Bytes.format(model.selectedBytes)) of junk is ready to clean. Open any row to review it first."
                : "Nothing left to clean right now. Your Mac is in good shape."
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 50) {
                HeroArt(name: "disc-care", size: 340, glow: NavItem.dashboard.gradient.glow, scanning: phase == .scanning)
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(subtitle)
                        .font(.system(size: 15.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 370, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(features.enumerated()), id: \.element.section) { i, feature in
                            FeatureRow(feature: feature, dimmed: phase == .idle) {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { model.section = feature.section }
                            }
                            .opacity(shown ? 1 : 0)
                            .offset(x: shown ? 0 : 24)
                            .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08 + Double(i) * 0.07), value: shown)
                        }
                    }
                    .padding(.top, 8)
                    .frame(width: 380)
                    Text(caption).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 4)
                }
                .animation(.easeOut(duration: 0.3), value: phase)
            }
            .offset(y: -34)
            VStack {
                Spacer()
                RoundActionButton(title: buttonTitle, tint: tint, progress: phase == .scanning ? model.smartProgress : nil) {
                    if phase == .done, model.selectedBytes > 0 { model.confirmClean() } else { model.smartScan() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .padding(.bottom, 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation { shown = true } }
    }

    private var buttonTitle: String {
        phase == .done && model.selectedBytes > 0 ? "Clean" : "Scan"
    }

    private var caption: String {
        switch phase {
        case .idle: return model.scan.map { "Sizes from your last scan, \(PanelView.relative($0.date))." } ?? "Run a scan to see what you can free."
        case .scanning: return "You can keep working while Diskwise scans."
        case .done: return "Clean removes the junk you have selected in Cleanup."
        }
    }

    struct Feature {
        let section: NavItem
        let title: String
        let value: String
        let loading: Bool
    }

    private var features: [Feature] {
        let large = model.largeFiles.reduce(0) { $0 + $1.size } + model.downloads.reduce(0) { $0 + $1.size }
        let stale = model.staleProjects
        let unused = model.apps.filter { $0.lastUsed.map { Date().timeIntervalSince($0) > 90 * 86_400 } ?? true }.count
        let scanningFiles = model.scanning || model.scan == nil
        return [
            Feature(section: .cleanup, title: "Junk Cleanup", value: Bytes.format(model.selectedBytes),
                    loading: model.cleanupLoading && model.groups.isEmpty),
            Feature(section: .files, title: "Large & Old Files", value: Bytes.format(large), loading: scanningFiles),
            Feature(section: .projects, title: "Project Junk",
                    value: stale.isEmpty ? "None idle" : Bytes.format(stale.reduce(0) { $0 + $1.size }), loading: scanningFiles),
            Feature(section: .apps, title: "Unused Apps", value: "\(unused) apps", loading: model.apps.isEmpty),
        ]
    }
}

private struct FeatureRow: View {
    let feature: SmartCareView.Feature
    let dimmed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Icon3D(name: feature.section.icon, symbol: feature.section.symbol, tint: feature.section.color, size: 32)
                Text(feature.title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(.white)
                Spacer(minLength: 12)
                if feature.loading {
                    Spinner(size: 12)
                } else {
                    Text(feature.value)
                        .font(Theme.number(14, .semibold))
                        .foregroundStyle(.white.opacity(dimmed ? 0.55 : 0.9))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: feature.value)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering ? 0.7 : 0))
                    .offset(x: hovering ? 0 : -4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Open \(feature.section.rawValue)")
    }
}

/// Free space over time.
struct ActivityView: View {
    @ObservedObject var model: AppModel
    @State private var days = 7

    var body: some View {
        let points = model.history.recent(days: days)
        let values = points.map(\.available)
        WindowPage(title: "Activity", subtitle: "How much free space your Mac had, sampled every 15 minutes.") {
            SegmentedTabs(items: [(7, "7 days"), (30, "30 days")], selection: $days).fixedSize()
        } content: {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Available space", detail: days == 7 ? "last 7 days" : "last 30 days")
                    if points.count >= 2 {
                        AreaChart(values: values.map(Double.init), color: NavItem.activity.color, height: 240)
                        HStack {
                            Text(points.first.map { $0.date.formatted(date: .abbreviated, time: .shortened) } ?? "")
                            Spacer()
                            Text("Now")
                        }
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    } else {
                        Text("Collecting data. The chart fills in over the next few hours.")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(20)
                .windowCard()
                HStack(spacing: 14) {
                    stat("Available now", model.disk.map { Bytes.format($0.available) } ?? "...")
                    stat("Change", model.history.change(days: days).map { "\($0 < 0 ? "-" : "+")\(Bytes.format(abs($0)))" } ?? "...")
                    stat("Lowest", values.min().map(Bytes.format) ?? "...")
                    stat("Highest", values.max().map(Bytes.format) ?? "...")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            Text(value).font(Theme.number(22)).foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .windowCard()
    }
}
