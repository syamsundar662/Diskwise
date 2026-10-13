import SwiftUI
import DiskwiseCore

// Four candidate layouts for the main window, rendered with real data so the
// look can be chosen before the full app is built.

enum WindowDesign: String, CaseIterable {
    case sidebar = "Sidebar"
    case focus = "Focus"
    case bento = "Bento"
    case lens = "Space Lens"
}

enum NavItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case cleanup = "Smart Cleanup"
    case lens = "Space Lens"
    case files = "Large & Old Files"
    case projects = "Project Junk"
    case apps = "Uninstaller"

    var id: String { rawValue }
    var short: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .cleanup: return "Cleanup"
        case .lens: return "Space Lens"
        case .files: return "Files"
        case .projects: return "Projects"
        case .apps: return "Apps"
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .cleanup: return "sparkles"
        case .lens: return "chart.pie.fill"
        case .files: return "doc.fill"
        case .projects: return "hammer.fill"
        case .apps: return "square.grid.2x2.fill"
        }
    }
    var color: Color {
        switch self {
        case .dashboard: return Theme.cyan
        case .cleanup: return Theme.teal
        case .lens: return Theme.blue
        case .files: return Theme.pink
        case .projects: return Theme.amber
        case .apps: return Theme.violet
        }
    }
}

struct MainWindowMock: View {
    @ObservedObject var model: AppModel
    let design: WindowDesign

    static let size = CGSize(width: 1080, height: 700)

    var body: some View {
        ZStack(alignment: .topLeading) {
            WindowBackdrop(glow: design == .focus)
            switch design {
            case .sidebar: SidebarDesign(model: model)
            case .focus: FocusDesign(model: model)
            case .bento: BentoDesign(model: model)
            case .lens: LensDesign(model: model)
            }
            TrafficLights().padding(.leading, 18).padding(.top, 18)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: Shared pieces

struct WindowBackdrop: View {
    var glow = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.glassTop, Theme.glassBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.cyan.opacity(glow ? 0.22 : 0.10), .clear],
                           center: glow ? UnitPoint(x: 0.55, y: 0.42) : UnitPoint(x: 0.2, y: 0), startRadius: 0,
                           endRadius: glow ? 420 : 520)
        }
    }
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

/// The app's mark: a pie slice on a blue rounded square.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.70, blue: 1.0), Color(red: 0.12, green: 0.34, blue: 0.86)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "chart.pie.fill").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: Theme.cyan.opacity(0.35), radius: 6, y: 2)
    }
}

extension AppModel {
    func badge(for item: NavItem) -> String? {
        switch item {
        case .dashboard: return nil
        case .cleanup: return Bytes.format(selectedBytes)
        case .lens: return scan.map { Bytes.format($0.root.size) }
        case .files: return "\(largeFiles.count + downloads.count)"
        case .projects: return projects.isEmpty ? nil : "\(projects.count)"
        case .apps: return "\(apps.count)"
        }
    }

    var topFolders: [FolderNode] { Array(scan?.root.children.prefix(6) ?? []) }
}

struct Sidebar: View {
    @ObservedObject var model: AppModel
    var selected: NavItem = .dashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                AppMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Diskwise").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Disk care for your Mac").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)
            .padding(.bottom, 18)
            ForEach(NavItem.allCases) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item == selected ? Theme.text : item.color).frame(width: 18)
                    Text(item.rawValue).font(.system(size: 12.5, weight: item == selected ? .semibold : .medium))
                        .foregroundStyle(item == selected ? Theme.text : Theme.secondary)
                    Spacer()
                    if let badge = model.badge(for: item) {
                        Text(badge).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary).monospacedDigit()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item == selected ? Theme.cyan.opacity(0.2) : .clear))
                .padding(.horizontal, 8)
            }
            Spacer()
            if let disk = model.disk {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "internaldrive.fill").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text(disk.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                    }
                    CapacityBar(fraction: disk.usedFraction, color: SpaceLevel(available: disk.available).color, height: 5)
                    Text("\(Bytes.format(disk.available)) free of \(Bytes.format(disk.total))")
                        .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
                .padding(12)
                .card(radius: 10)
                .padding(12)
            }
        }
        .frame(width: 228)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.text)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
    }
}

extension AppModel {
    var scannedLine: String {
        guard let scan else { return "Not scanned yet" }
        return "\(disk?.name ?? "Macintosh HD"), scanned \(PanelView.relative(scan.date))"
    }
}

struct DiskRing: View {
    @ObservedObject var model: AppModel
    var size: CGFloat = 150
    var showsAvailable = false

    var body: some View {
        let level = SpaceLevel(available: model.disk?.available ?? .max)
        ZStack {
            TickRing(progress: model.disk?.usedFraction ?? 0, colors: level.ringColors,
                     ticks: size > 200 ? 90 : 64, tickLength: size * 0.075, tickWidth: size > 200 ? 3.6 : 3)
            VStack(spacing: 2) {
                if showsAvailable, let disk = model.disk {
                    Text(Bytes.format(disk.available)).font(Theme.number(size * 0.15)).foregroundStyle(Theme.text)
                    Text("available of \(Bytes.format(disk.total))").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                } else {
                    Text("\(model.disk?.usedPercent ?? 0)%").font(Theme.number(size * 0.2)).foregroundStyle(Theme.text)
                    Text("used").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct CategoryLegend: View {
    let parts: [(StorageCategory, Int64)]
    var columns = 3

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: columns),
                  alignment: .leading, spacing: 6) {
            ForEach(parts.filter { $0.1 > 0 }, id: \.0) { category, size in
                HStack(spacing: 5) {
                    Circle().fill(category.color).frame(width: 7, height: 7)
                    Text(category.rawValue).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(Bytes.format(size)).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
        }
    }
}

struct HistoryChart: View {
    @ObservedObject var model: AppModel
    var height: CGFloat = 90

    var body: some View {
        let points = model.history.recent(days: 7)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Available space", detail: "last 7 days")
                Spacer()
                if let change = model.history.change(days: 7), abs(change) >= 100 * Bytes.mb {
                    Text("\(change < 0 ? "-" : "+")\(Bytes.format(abs(change)))")
                        .font(Theme.number(11, .semibold)).foregroundStyle(change < 0 ? Theme.amber : Theme.green)
                }
            }
            if points.count >= 2 {
                AreaChart(values: points.map { Double($0.available) }, height: height)
            } else {
                Text("Collecting data. The chart fills in over the next few hours.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity, minHeight: height, alignment: .center)
            }
        }
    }
}

struct TopFolders: View {
    @ObservedObject var model: AppModel
    var count = 5
    var colors: [Color]? = nil

    var body: some View {
        let folders = Array(model.topFolders.prefix(count))
        let biggest = folders.first?.size ?? 1
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(folders.enumerated()), id: \.offset) { i, folder in
                HStack(spacing: 9) {
                    if let colors {
                        RoundedRectangle(cornerRadius: 3).fill(colors[i % colors.count]).frame(width: 10, height: 10)
                    } else {
                        FileIcon(path: NSHomeDirectory() + "/" + folder.name, size: 18)
                    }
                    Text(folder.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    CapacityBar(fraction: Double(folder.size) / Double(max(biggest, 1)), color: (colors?[i % colors!.count] ?? Theme.cyan).opacity(0.85))
                        .frame(width: 80)
                    Text(Bytes.format(folder.size)).font(Theme.number(11.5, .semibold)).foregroundStyle(Theme.text)
                        .frame(width: 62, alignment: .trailing)
                }
            }
        }
    }
}

struct ToolCard: View {
    let item: NavItem
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconChip(symbol: item.symbol, color: item.color, size: 32)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.rawValue).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.secondary)
                Text(value).font(Theme.number(20)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }
}

extension AppModel {
    var toolValues: [(NavItem, String, String)] {
        let large = largeFiles.reduce(0) { $0 + $1.size } + downloads.reduce(0) { $0 + $1.size }
        let stale = staleProjects
        let unused = apps.filter { $0.lastUsed.map { Date().timeIntervalSince($0) > 90 * 86_400 } ?? true }
        return [
            (.files, Bytes.format(large), "\(largeFiles.count) big files, \(downloads.count) old downloads"),
            (.projects, Bytes.format(projects.reduce(0) { $0 + $1.size }), "\(stale.count) idle of \(projects.count) folders"),
            (.apps, "\(apps.count) apps", "\(unused.count) unused for 3 months"),
        ]
    }
}

struct CleanButton: View {
    let title: String
    var large = false

    var body: some View {
        Text(title)
            .font(.system(size: large ? 15 : 12.5, weight: .semibold))
            .foregroundStyle(Theme.onCyan)
            .padding(.horizontal, large ? 34 : 16)
            .padding(.vertical, large ? 13 : 8)
            .frame(maxWidth: large ? nil : .infinity)
            .background(Capsule().fill(LinearGradient(colors: [Theme.cyan, Theme.cyan.opacity(0.78)], startPoint: .top, endPoint: .bottom)))
            .shadow(color: Theme.cyan.opacity(large ? 0.45 : 0.25), radius: large ? 16 : 8, y: 4)
    }
}

// MARK: 1. Sidebar

struct SidebarDesign: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    PageHeader(title: "Dashboard", subtitle: model.scannedLine)
                    Spacer()
                    Label("Rescan", systemImage: "arrow.clockwise").font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.text).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.09)))
                }
                HStack(spacing: 16) {
                    HStack(spacing: 22) {
                        DiskRing(model: model, size: 150)
                        VStack(alignment: .leading, spacing: 9) {
                            if let disk = model.disk {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(Bytes.format(disk.available)).font(Theme.number(30)).foregroundStyle(Theme.text)
                                    Text("available").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                                }
                                Text("\(Bytes.format(disk.used)) used of \(Bytes.format(disk.total))")
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                                DiskBar(parts: model.breakdown, total: disk.total).padding(.top, 4)
                                CategoryLegend(parts: model.breakdown, columns: 2).padding(.top, 2)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .card(radius: 16)
                    VStack(alignment: .leading, spacing: 10) {
                        IconChip(symbol: "sparkles", color: Theme.cyan, size: 34)
                        Text(Bytes.format(model.selectedBytes)).font(Theme.number(28)).foregroundStyle(Theme.text)
                        Text("ready to clean safely").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        VStack(spacing: 5) {
                            ForEach(model.groups.filter { $0.selectedByDefault }.sorted { $0.size > $1.size }.prefix(3)) { group in
                                HStack {
                                    Text(group.title).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                                    Spacer()
                                    Text(Bytes.format(group.size)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        CleanButton(title: "Clean now")
                    }
                    .padding(18)
                    .frame(width: 250)
                    .frame(maxHeight: .infinity)
                    .card(radius: 16)
                }
                .frame(height: 250)
                HStack(spacing: 16) {
                    ForEach(model.toolValues, id: \.0) { item, value, detail in ToolCard(item: item, value: value, detail: detail) }
                }
                HStack(spacing: 16) {
                    HistoryChart(model: model, height: 70).padding(16).frame(maxWidth: .infinity).card(radius: 16)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Biggest folders", detail: "in Home")
                        TopFolders(model: model, count: 3)
                    }
                    .padding(16).frame(maxWidth: .infinity).card(radius: 16)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
    }
}

// MARK: 2. Focus

struct FocusDesign: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                AppMark(size: 34).padding(.top, 52).padding(.bottom, 14)
                ForEach(NavItem.allCases) { item in
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item == .dashboard ? Theme.text : Theme.tertiary)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(item == .dashboard ? Theme.cyan.opacity(0.22) : .clear))
                }
                Spacer()
                Image(systemName: "gearshape.fill").font(.system(size: 14)).foregroundStyle(Theme.tertiary).padding(.bottom, 20)
            }
            .frame(width: 76)
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.2))

            VStack(spacing: 22) {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Text("Your disk is \(model.disk?.usedPercent ?? 0)% full").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Diskwise found \(Bytes.format(model.selectedBytes)) you can safely remove.")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                }
                DiskRing(model: model, size: 270, showsAvailable: true)
                VStack(spacing: 10) {
                    CleanButton(title: "Clean \(Bytes.format(model.selectedBytes))", large: true)
                    Text("Review details").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.cyan)
                }
                HStack(spacing: 12) {
                    ForEach(model.toolValues, id: \.0) { item, value, _ in
                        HStack(spacing: 10) {
                            IconChip(symbol: item.symbol, color: item.color, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(value).font(Theme.number(14)).foregroundStyle(Theme.text)
                                Text(item.rawValue).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .card(radius: 14)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: 3. Bento

struct BentoDesign: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer().frame(width: 70)
                AppMark(size: 24)
                Text("Diskwise").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(NavItem.allCases) { item in
                        Text(item.short).font(.system(size: 12, weight: item == .dashboard ? .semibold : .medium))
                            .foregroundStyle(item == .dashboard ? Theme.text : Theme.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(item == .dashboard ? Color.white.opacity(0.14) : .clear))
                    }
                }
                .padding(3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                Spacer()
                IconButton(symbol: "arrow.clockwise") {}
                IconButton(symbol: "gearshape.fill") {}
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            Hairline()
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    VStack(spacing: 10) {
                        DiskRing(model: model, size: 150)
                        if let disk = model.disk {
                            Text("\(Bytes.format(disk.available)) available").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                        }
                    }
                    .padding(18).frame(width: 230).frame(maxHeight: .infinity).card(radius: 18)
                    HStack(spacing: 18) {
                        Donut(parts: model.breakdown, total: model.disk?.total ?? 1).frame(width: 150, height: 150)
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "What's using space")
                            CategoryLegend(parts: model.breakdown, columns: 1)
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).card(radius: 18)
                    VStack(alignment: .leading, spacing: 8) {
                        IconChip(symbol: "sparkles", color: Theme.cyan, size: 32)
                        Spacer(minLength: 0)
                        Text(Bytes.format(model.selectedBytes)).font(Theme.number(30)).foregroundStyle(Theme.text)
                        Text("safe to clean now").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        CleanButton(title: "Clean").padding(.top, 6)
                    }
                    .padding(18).frame(width: 220).frame(maxHeight: .infinity, alignment: .leading).card(radius: 18)
                }
                .frame(height: 236)
                HStack(spacing: 14) {
                    HistoryChart(model: model, height: 96).padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).card(radius: 18)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Biggest folders", detail: "in Home")
                        TopFolders(model: model, count: 4)
                    }
                    .padding(18).frame(width: 400).frame(maxHeight: .infinity, alignment: .top).card(radius: 18)
                }
                .frame(height: 170)
                HStack(spacing: 14) {
                    ForEach(model.toolValues, id: \.0) { item, value, detail in ToolCard(item: item, value: value, detail: detail) }
                }
            }
            .padding(18)
        }
    }
}

/// Categories as a ring of arcs around the used space.
struct Donut: View {
    let parts: [(StorageCategory, Int64)]
    let total: Int64

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 10
            var angle = -Double.pi / 2
            ctx.stroke(Path { $0.addArc(center: center, radius: radius, startAngle: .zero, endAngle: .degrees(360), clockwise: false) },
                       with: .color(Theme.track), lineWidth: 18)
            for (category, value) in parts where value > 0 {
                let sweep = 2 * Double.pi * Double(value) / Double(max(total, 1))
                var arc = Path()
                arc.addArc(center: center, radius: radius, startAngle: .radians(angle + 0.02), endAngle: .radians(angle + sweep - 0.02), clockwise: false)
                ctx.stroke(arc, with: .color(category.color), style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                angle += sweep
            }
        }
        .overlay {
            VStack(spacing: 0) {
                Text(Bytes.format(parts.reduce(0) { $0 + $1.1 })).font(Theme.number(17)).foregroundStyle(Theme.text)
                Text("used").font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

// MARK: 4. Space Lens

struct LensDesign: View {
    @ObservedObject var model: AppModel
    static let colors: [Color] = [Theme.cyan, Theme.violet, Theme.teal, Theme.amber, Theme.pink, Theme.blue,
                                  Color(red: 0.55, green: 0.85, blue: 0.4)]

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, selected: .lens)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    PageHeader(title: "Space Lens", subtitle: "Your home folder by size. Click a ring to go inside.")
                    Spacer()
                    HStack(spacing: 8) {
                        Text("\(Bytes.format(model.disk?.available ?? 0)) free").font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.text).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.09)))
                        CleanButton(title: "Clean \(Bytes.format(model.selectedBytes))").fixedSize()
                    }
                }
                HStack(alignment: .center, spacing: 26) {
                    if let root = model.scan?.root {
                        Sunburst(root: root, colors: Self.colors)
                            .frame(width: 430, height: 430)
                            .overlay {
                                VStack(spacing: 2) {
                                    Text(Bytes.format(root.size)).font(Theme.number(24)).foregroundStyle(Theme.text)
                                    Text("Home").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                                }
                            }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Biggest in Home")
                        TopFolders(model: model, count: 7, colors: Self.colors)
                        Hairline().padding(.vertical, 4)
                        HStack(spacing: 8) {
                            IconChip(symbol: "lightbulb.fill", color: Theme.amber, size: 24)
                            Text("Library holds app data and caches. Smart Cleanup handles the safe parts.")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .card(radius: 16)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
    }
}

/// Folders as rings: the inner ring is the home folder's children, outer rings
/// their children, each arc sized by bytes.
struct Sunburst: View {
    let root: FolderNode
    var depth = 3
    let colors: [Color]

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerMost = min(size.width, size.height) / 2
            let inner0 = outerMost * 0.30
            let ring = (outerMost - inner0) / CGFloat(depth) - 3

            func sector(_ inner: CGFloat, _ outer: CGFloat, _ a0: Double, _ a1: Double) -> Path {
                var p = Path()
                p.addArc(center: center, radius: outer, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                p.addArc(center: center, radius: inner, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
                p.closeSubpath()
                return p
            }

            func draw(_ node: FolderNode, level: Int, start: Double, span: Double, color: Color?) {
                var angle = start
                let inner = inner0 + CGFloat(level - 1) * (ring + 3)
                for (i, child) in node.children.enumerated() {
                    let sweep = span * Double(child.size) / Double(max(node.size, 1))
                    defer { angle += sweep }
                    guard sweep > 0.006 else { continue }
                    let base = color ?? colors[i % colors.count]
                    let opacity = level == 1 ? 0.95 : level == 2 ? 0.62 : 0.38
                    let gap = min(0.008, sweep * 0.2)
                    ctx.fill(sector(inner, inner + ring, angle + gap / 2, angle + sweep - gap / 2), with: .color(base.opacity(opacity)))
                    if level < depth, child.isDirectory { draw(child, level: level + 1, start: angle, span: sweep, color: base) }
                }
            }
            draw(root, level: 1, start: -Double.pi / 2, span: 2 * Double.pi, color: nil)
        }
    }
}
