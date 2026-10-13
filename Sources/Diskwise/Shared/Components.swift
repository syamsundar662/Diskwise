import AppKit
import SwiftUI
import DiskwiseCore

// Custom building blocks in the violet glass style. Everything except the
// blurred glass is drawn in SwiftUI, so snapshots show it as is.

/// Blurred desktop behind the panel, with rounded corners. Behind-window blur
/// needs AppKit, so off-screen snapshots use the plain tint instead.
struct GlassBlur: NSViewRepresentable {
    var radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.appearance = NSAppearance(named: .darkAqua)
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: radius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

struct GlassBackground: View {
    var radius: CGFloat
    var live: Bool

    var body: some View {
        ZStack {
            if live { GlassBlur(radius: radius) }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Theme.glassTop, Theme.glassBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(live ? Theme.glassOpacity : 1)
        }
    }
}

extension View {
    func glassPanel(live: Bool, radius: CGFloat = 14) -> some View {
        self
            .background(GlassBackground(radius: radius, live: live))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
    }

    func card(radius: CGFloat = 12, fill: Color = Theme.card) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border))
    }
}

/// SF Symbol on a softly tinted rounded chip.
struct IconChip: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(0.18)))
    }
}

/// Finder's icon for a file, folder or app.
struct FileIcon: View {
    let path: String
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct SectionLabel: View {
    let text: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text.opacity(0.88))
            if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.tertiary) }
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1) }
}

/// Ring of short ticks filled with a glowing two-color gradient, like
/// CleanMyMac's gauges. Animatable: changes to `progress` sweep smoothly.
struct TickRing: View, Animatable {
    var progress: Double
    let colors: (Color, Color)
    var ticks = 48
    var tickLength: CGFloat = 8
    var tickWidth: CGFloat = 3

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2 - tickWidth / 2
            let inner = outer - tickLength
            let filled = Int((min(max(progress, 0), 1) * Double(ticks)).rounded())
            let style = StrokeStyle(lineWidth: tickWidth, lineCap: .round)
            func tick(_ i: Int) -> Path {
                let angle = CGFloat((-90 + 360 * Double(i) / Double(ticks)) * Double.pi / 180)
                var p = Path()
                p.move(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
                p.addLine(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
                return p
            }
            for i in filled..<ticks { ctx.stroke(tick(i), with: .color(Theme.track), style: style) }
            let start = NSColor(colors.0), end = NSColor(colors.1)
            var glow = ctx
            glow.addFilter(.shadow(color: colors.1.opacity(0.55), radius: 4))
            for i in 0..<filled {
                let t = filled > 1 ? CGFloat(i) / CGFloat(filled - 1) : 0
                let color = start.blended(withFraction: t, of: end) ?? start
                glow.stroke(tick(i), with: .color(Color(nsColor: color)), style: style)
            }
        }
    }
}

struct CapacityBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: max(geo.size.width * min(max(fraction, 0), 1), fraction > 0 ? 2 : 0))
            }
        }
        .frame(height: height)
    }
}

/// The disk as one bar: a colored segment per category, the free part as track.
struct DiskBar: View {
    let parts: [(StorageCategory, Int64)]
    let total: Int64

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(parts.filter { $0.1 > 0 }, id: \.0) { category, size in
                    Rectangle().fill(category.color)
                        .frame(width: max(3, (geo.size.width - CGFloat(parts.count) * 2) * CGFloat(size) / CGFloat(max(total, 1))))
                }
                Rectangle().fill(Theme.track)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}

/// Available space over time as a soft area chart.
struct AreaChart: View {
    let values: [Double]
    var color = Theme.cyan
    var height: CGFloat = 44

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let low = values.min(), let high = values.max() else { return }
            let span = max(high - low, high * 0.02, 1)
            let floor = max(low - span * 0.35, 0), top = high + span * 0.15
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: size.height * (1 - CGFloat((values[i] - floor) / (top - floor))))
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0.02)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        .frame(height: height)
    }
}

/// Capsule button with hover. `prominent` fills it cyan, `destructive` red.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, destructive: destructive)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let prominent: Bool
        let destructive: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(prominent ? Theme.onCyan : destructive ? Color.white : Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var fill: Color {
            let strength = configuration.isPressed ? 0.75 : hovering ? 1 : 0.9
            if prominent { return Theme.cyan.opacity(strength) }
            if destructive { return Theme.red.opacity(strength * 0.85) }
            return Color.white.opacity(configuration.isPressed ? 0.18 : hovering ? 0.14 : 0.08)
        }
    }
}

/// Round icon button with hover.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 24
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(tint ?? (hovering ? Theme.text : Theme.secondary))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Row in the custom dropdown menu.
struct MenuRow: View {
    let symbol: String
    let title: String
    var destructive = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 14)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Theme.red : Theme.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct Spinner: View {
    var size: CGFloat = 12
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 1)
            .stroke(Theme.secondary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spinning = true }
            }
    }
}

/// Round checkbox; `mixed` shows a dash for partly selected groups.
struct Checkbox: View {
    let checked: Bool
    var mixed = false
    var disabled = false
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Circle().strokeBorder(checked || mixed ? Color.clear : Color.white.opacity(0.35), lineWidth: 1.4)
                if checked || mixed {
                    Circle().fill(Theme.cyan)
                    Image(systemName: mixed && !checked ? "minus" : "checkmark")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(Theme.onCyan)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

/// Two- or three-way switch.
struct SegmentedTabs<ID: Hashable>: View {
    let items: [(id: ID, title: String)]
    @Binding var selection: ID
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.id) { item in
                let selected = item.id == selection
                Text(item.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.text : Theme.tertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { selection = item.id } }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

struct RowAction: Identifiable {
    let symbol: String
    let help: String
    var destructive = false
    let action: () -> Void
    var id: String { symbol }
}

/// One line in a list page: optional checkbox, icon, title with a muted
/// subtitle, size on the right. Actions show on hover; rows with `onOpen`
/// drill in.
struct ListRow<Icon: View>: View {
    var checked: Bool? = nil
    var toggle: () -> Void = {}
    var checkDisabled = false
    @ViewBuilder let icon: () -> Icon
    let title: String
    var badge: String? = nil
    var subtitle: String? = nil
    var warning: String? = nil
    /// nil shows a spinner.
    var size: Int64?
    var showsSize = true
    /// Fills a faint bar behind the size, relative to the biggest row.
    var fraction: Double? = nil
    var actions: [RowAction] = []
    var onOpen: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            if let checked { Checkbox(checked: checked, disabled: checkDisabled, toggle: toggle) }
            icon()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                        .lineLimit(1).truncationMode(.middle)
                    if let badge {
                        Text(badge).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.09)))
                            .fixedSize()
                    }
                }
                if let warning {
                    Text(warning).font(.system(size: 10.5)).foregroundStyle(Theme.amber).lineLimit(1)
                } else if let subtitle {
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if hovering, !actions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(actions) { action in
                        IconButton(symbol: action.symbol, size: 22, tint: action.destructive ? Theme.red : nil,
                                   action: action.action)
                            .help(action.help)
                    }
                }
            }
            if showsSize {
            VStack(alignment: .trailing, spacing: 3) {
                if let size {
                    Text(Bytes.format(size)).font(Theme.number(12, .semibold)).foregroundStyle(Theme.text).monospacedDigit()
                } else {
                    Spinner(size: 11)
                }
                if let fraction { CapacityBar(fraction: fraction, color: Theme.cyan.opacity(0.8), height: 3).frame(width: 54) }
            }
            .frame(minWidth: 62, alignment: .trailing)
            }
            if onOpen != nil {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if let onOpen { onOpen() } else if checked != nil, !checkDisabled { toggle() } }
    }
}

/// A list area of fixed height: scrolls in the live panel, clipped in snapshots
/// (off-screen renders can't draw scroll views).
struct ListArea<Content: View>: View {
    var live: Bool
    /// nil fills the space it's given (window pages).
    var height: CGFloat? = 330
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if live {
                ScrollView { VStack(spacing: 0) { content() }.padding(.vertical, 4) }
                    .scrollIndicators(.never)
            } else {
                // Both bounds, so the frame takes the space offered instead of the list's full height.
                VStack(spacing: 0) { content() }.padding(.vertical, 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 0, maxHeight: height ?? .infinity, alignment: .top)
                    .clipped()
            }
        }
        .frame(height: height)
        .frame(minHeight: 0, maxHeight: height == nil ? .infinity : nil)
    }
}

/// A bright comet that circles the ring while a scan runs.
struct ScanSweep: View {
    var ticks = 90
    var tickLength: CGFloat = 20
    var tickWidth: CGFloat = 3.6
    var color = Theme.cyan

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let head = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 * 2 * Double.pi
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = min(size.width, size.height) / 2 - tickWidth / 2
                let inner = outer - tickLength
                var glow = ctx
                glow.addFilter(.shadow(color: color.opacity(0.7), radius: 5))
                for i in 0..<ticks {
                    let angle = 2 * Double.pi * Double(i) / Double(ticks)
                    var behind = head - angle
                    if behind < 0 { behind += 2 * Double.pi }
                    let tail = 1.6
                    guard behind < tail else { continue }
                    let strength = 1 - behind / tail
                    let a = CGFloat(angle - Double.pi / 2)
                    var p = Path()
                    p.move(to: CGPoint(x: center.x + inner * cos(a), y: center.y + inner * sin(a)))
                    p.addLine(to: CGPoint(x: center.x + outer * cos(a), y: center.y + outer * sin(a)))
                    glow.stroke(p, with: .color(color.opacity(strength)), style: StrokeStyle(lineWidth: tickWidth, lineCap: .round))
                }
            }
        }
    }
}

/// A byte count that rolls its digits when it changes.
struct RollingBytes: View {
    let bytes: Int64
    var font: Font = Theme.number(30)
    var color: Color = Theme.text

    var body: some View {
        Text(Bytes.format(bytes))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(bytes)))
            .animation(.snappy(duration: 0.45), value: bytes)
    }
}

/// Custom switch: a capsule with a sliding knob.
struct PillToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.cyan : Color.white.opacity(0.16))
            .frame(width: 38, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 18, height: 18).padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() } }
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Lifts slightly and brightens its border on hover.
struct HoverLift: ViewModifier {
    var radius: CGFloat = 14
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.015 : 1)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.cyan.opacity(hovering ? 0.35 : 0)))
            .shadow(color: .black.opacity(hovering ? 0.3 : 0), radius: 12, y: 6)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(radius: CGFloat = 14) -> some View { modifier(HoverLift(radius: radius)) }
}

struct EmptyNote: View {
    let symbol: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .regular)).foregroundStyle(Theme.tertiary)
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}

/// Off-screen renders show animations in their final state.
enum RenderMode {
    static var snapshot = false
}

/// Path shown relative to home: "~/My Projects/site".
func shortPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
