import SwiftUI
import DiskwiseCore

/// The home folder as a sunburst: the inner ring is the current folder's
/// contents, outer rings go one level deeper. Hover to see a folder, click to
/// zoom in, click the center to go back out.
struct LensView: View {
    @ObservedObject var model: AppModel
    var live = true
    @State private var path: [String] = []
    @State private var hovered: [String]?

    static let colors: [Color] = [Theme.cyan, Theme.violet, Theme.teal, Theme.amber, Theme.pink, Theme.blue,
                                  Color(red: 0.55, green: 0.85, blue: 0.40), Color(red: 1.0, green: 0.62, blue: 0.45)]

    private var root: FolderNode? { model.scan?.root.node(at: path.joined(separator: "/")) }
    private var home: String { NSHomeDirectory() }

    var body: some View {
        WindowPage(title: "Space Lens", subtitle: "Your home folder by size. Click a ring to go inside, the center to go back.") {
            HStack(spacing: 8) {
                if let disk = model.disk {
                    Text("\(Bytes.format(disk.available)) free").font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.text).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.09)))
                }
                Button(model.scanning ? "Scanning..." : "Rescan") { model.startScan() }
                    .buttonStyle(PillButtonStyle()).disabled(model.scanning)
            }
        } content: {
            if let root {
                HStack(alignment: .center, spacing: 26) {
                    chart(root).frame(maxWidth: .infinity)
                    inspector(root).frame(width: 330)
                }
            } else {
                EmptyNote(symbol: "chart.pie", title: model.scanning ? "Scanning your home folder..." : "Nothing scanned yet",
                          detail: model.scanning ? "\(Bytes.format(model.scanProgress?.bytes ?? 0)) checked so far." : "Run a scan to see your folders.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Chart

    private func chart(_ root: FolderNode) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let layout = SunburstLayout(root: root, colors: Self.colors, size: side)
            ZStack {
                SunburstCanvas(layout: layout, hovered: hovered)
                    .id(path)
                    .transition(.asymmetric(insertion: .scale(scale: 0.82).combined(with: .opacity),
                                            removal: .scale(scale: 1.12).combined(with: .opacity)))
                centerLabel(root, layout: layout)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = layout.segment(at: point)?.path
                case .ended: hovered = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { point in
                if let segment = layout.segment(at: point) {
                    if segment.canOpen { zoom(to: path + segment.path) }
                } else if layout.isCenter(point), !path.isEmpty {
                    zoom(to: Array(path.dropLast()))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func centerLabel(_ root: FolderNode, layout: SunburstLayout) -> some View {
        let segment = hovered.flatMap { h in layout.segments.first { $0.path == h } }
        return VStack(spacing: 3) {
            Text(segment?.name ?? (path.last ?? "Home"))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                .lineLimit(1).truncationMode(.middle)
            RollingBytes(bytes: segment?.size ?? root.size, font: Theme.number(26))
            if let segment {
                Text("\(Int((Double(segment.size) / Double(max(root.size, 1)) * 100).rounded()))% of \(path.last ?? "Home")")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
            } else if !path.isEmpty {
                Label("Back", systemImage: "arrow.uturn.backward").font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
            }
        }
        .frame(width: layout.innerRadius * 1.6)
        .allowsHitTesting(false)
    }

    private func zoom(to newPath: [String]) {
        hovered = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { path = newPath }
    }

    // MARK: Inspector

    private func inspector(_ root: FolderNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumb.padding(14)
            Hairline()
            ListArea(live: live, height: nil) {
                ForEach(Array(root.children.prefix(40).enumerated()), id: \.element.id) { i, child in
                    row(child, index: i, parent: root)
                }
                if root.restCount > 0 {
                    ListRow(icon: { RoundedRectangle(cornerRadius: 3).fill(Theme.gray).frame(width: 10, height: 10) },
                            title: "\(root.restCount) smaller items", size: root.restSize)
                }
            }
            .padding(.horizontal, 4)
        }
        .windowCard()
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            crumb("Home", depth: 0)
            ForEach(Array(path.enumerated()), id: \.offset) { i, name in
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.tertiary)
                crumb(name, depth: i + 1)
            }
            Spacer(minLength: 0)
        }
    }

    private func crumb(_ name: String, depth: Int) -> some View {
        let current = depth == path.count
        return Button(name) { zoom(to: Array(path.prefix(depth))) }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: current ? .semibold : .medium))
            .foregroundStyle(current ? Theme.text : Theme.cyan)
            .lineLimit(1)
            .disabled(current)
    }

    private func row(_ child: FolderNode, index: Int, parent: FolderNode) -> some View {
        let full = ([home] + path + [child.name]).joined(separator: "/")
        var actions = [RowAction(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(full) }]
        if SafeDelete.refusal(for: full) == nil {
            actions.append(RowAction(symbol: "trash", help: "Move to Trash", destructive: true) {
                model.confirmTrash([full], sizes: [child.size])
            })
        }
        let canOpen = child.isDirectory && !child.children.isEmpty
        return ListRow(icon: { RoundedRectangle(cornerRadius: 3).fill(Self.colors[index % Self.colors.count]).frame(width: 10, height: 10) },
                       title: child.name,
                       subtitle: "\(Int((Double(child.size) / Double(max(parent.size, 1)) * 100).rounded()))%",
                       size: child.size,
                       actions: actions,
                       onOpen: canOpen ? { zoom(to: path + [child.name]) } : nil)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovered == [child.name] ? Color.white.opacity(0.06) : .clear))
            .onHover { inside in hovered = inside ? [child.name] : (hovered == [child.name] ? nil : hovered) }
    }
}

/// Where every arc of the sunburst goes, shared by drawing and hit testing.
struct SunburstLayout {
    struct Segment {
        /// Path below the chart's root, e.g. ["Library", "Caches"].
        let path: [String]
        let name: String
        let level: Int
        /// Angles in radians, clockwise from 12 o'clock.
        let start: Double
        let end: Double
        let color: Color
        let size: Int64
        let canOpen: Bool
    }

    static let depth = 3
    let center: CGPoint
    let innerRadius: CGFloat
    let ring: CGFloat
    let gap: CGFloat = 3
    private(set) var segments: [Segment] = []

    init(root: FolderNode, colors: [Color], size: CGFloat) {
        center = CGPoint(x: size / 2, y: size / 2)
        let outer = size / 2 - 4
        innerRadius = outer * 0.32
        ring = (outer - innerRadius) / CGFloat(Self.depth) - gap
        var result: [Segment] = []
        func walk(_ node: FolderNode, path: [String], level: Int, start: Double, span: Double, color: Color?) {
            var angle = start
            for (i, child) in node.children.enumerated() {
                let sweep = span * Double(child.size) / Double(max(node.size, 1))
                defer { angle += sweep }
                guard sweep > 0.005 else { continue }
                let base = color ?? colors[i % colors.count]
                let childPath = path + [child.name]
                result.append(Segment(path: childPath, name: child.name, level: level, start: angle, end: angle + sweep,
                                      color: base, size: child.size, canOpen: child.isDirectory && !child.children.isEmpty))
                if level < Self.depth, child.isDirectory {
                    walk(child, path: childPath, level: level + 1, start: angle, span: sweep, color: base)
                }
            }
        }
        walk(root, path: [], level: 1, start: 0, span: 2 * Double.pi, color: nil)
        segments = result
    }

    func radii(_ level: Int) -> (CGFloat, CGFloat) {
        let inner = innerRadius + CGFloat(level - 1) * (ring + gap)
        return (inner, inner + ring)
    }

    func segment(at point: CGPoint) -> Segment? {
        let dx = point.x - center.x, dy = point.y - center.y
        let r = sqrt(dx * dx + dy * dy)
        var angle = atan2(Double(dy), Double(dx)) + Double.pi / 2
        if angle < 0 { angle += 2 * Double.pi }
        return segments.first { s in
            let (inner, outer) = radii(s.level)
            return r >= inner && r <= outer && angle >= s.start && angle < s.end
        }
    }

    func isCenter(_ point: CGPoint) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        return sqrt(dx * dx + dy * dy) < innerRadius
    }
}

struct SunburstCanvas: View {
    let layout: SunburstLayout
    let hovered: [String]?

    var body: some View {
        Canvas { ctx, _ in
            for s in layout.segments {
                let (inner, outer) = layout.radii(s.level)
                let gap = min(0.008, (s.end - s.start) * 0.2)
                let a0 = s.start - Double.pi / 2 + gap / 2, a1 = s.end - Double.pi / 2 - gap / 2
                var p = Path()
                p.addArc(center: layout.center, radius: outer, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                p.addArc(center: layout.center, radius: inner, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
                p.closeSubpath()
                let base = s.level == 1 ? 0.95 : s.level == 2 ? 0.62 : 0.4
                let highlighted = hovered.map { s.path.starts(with: $0) } ?? false
                let opacity = hovered == nil ? base : highlighted ? min(base + 0.25, 1) : base * 0.45
                ctx.fill(p, with: .color(s.color.opacity(opacity)))
                if hovered == s.path {
                    ctx.stroke(p, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}
