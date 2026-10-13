import AppKit
import SwiftUI
import DiskwiseCore

// Ten candidate designs for the main window in the style of CleanMyMac's
// module pages (color per section, glossy hero object, feature list, round
// Scan button). Rendered with real data so one can be chosen.

enum CareDesign: Int, CaseIterable {
    case classic, aurora, split, glassCards, orbit, mono, bento, floating, steps, light

    var title: String {
        switch self {
        case .classic: return "Classic Care"
        case .aurora: return "Aurora"
        case .split: return "Split Hero"
        case .glassCards: return "Glass Cards"
        case .orbit: return "Orbit"
        case .mono: return "Monochrome Pro"
        case .bento: return "Bento Care"
        case .floating: return "Floating Sidebar"
        case .steps: return "Steps"
        case .light: return "Light Fresh"
        }
    }
}

struct CareWindowMock: View {
    @ObservedObject var model: AppModel
    let design: CareDesign

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch design {
            case .classic: ClassicCare(model: model)
            case .aurora: AuroraCare(model: model)
            case .split: SplitCare(model: model)
            case .glassCards: GlassCardsCare(model: model)
            case .orbit: OrbitCare(model: model)
            case .mono: MonoCare(model: model)
            case .bento: BentoCare(model: model)
            case .floating: FloatingCare(model: model)
            case .steps: StepsCare(model: model)
            case .light: LightCare(model: model)
            }
            TrafficLights().padding(.leading, 18).padding(.top, 18)
        }
        .frame(width: 1120, height: 740)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, design == .light ? .light : .dark)
    }
}

// MARK: Shared pieces

/// 3D artwork from Resources/Art: the app bundle when shipped, the repo during development.
enum Art {
    private static let repoFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Art")
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let image = Bundle.main.image(forResource: name)
            ?? NSImage(contentsOf: repoFolder.appendingPathComponent(name + ".png"))
        cache[name] = image
        return image
    }
}

/// A 3D hero object with a soft colored glow under it.
struct HeroArt: View {
    let name: String
    var size: CGFloat
    var glow: Color

    var body: some View {
        ZStack {
            Ellipse().fill(glow.opacity(0.55)).frame(width: size * 0.8, height: size * 0.22)
                .blur(radius: size * 0.09).offset(y: size * 0.42)
            Circle().fill(glow.opacity(0.22)).frame(width: size * 0.9).blur(radius: size * 0.16)
            if let image = Art.image(name) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A small 3D icon, falling back to the drawn glossy chip until its art exists.
struct Icon3D: View {
    let name: String
    let symbol: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        if let image = Art.image(name) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: size * 1.25, height: size * 1.25)
                .frame(width: size, height: size)
        } else {
            GlossyChip(symbol: symbol, tint: tint, size: size)
        }
    }
}

extension Color {
    /// Blends toward another color (0 keeps this one, 1 gives the other).
    func mix(_ other: Color, _ amount: CGFloat) -> Color {
        Color(nsColor: NSColor(self).usingColorSpace(.deviceRGB)?
            .blended(withFraction: amount, of: NSColor(other).usingColorSpace(.deviceRGB) ?? .white) ?? NSColor(self))
    }

    init(_ r: Double, _ g: Double, _ b: Double) { self.init(red: r, green: g, blue: b) }
}

struct CareFeature: Identifiable {
    let icon: String
    let symbol: String
    let title: String
    let value: String
    let color: Color
    var id: String { title }
}

extension AppModel {
    var careFeatures: [CareFeature] {
        let large = largeFiles.reduce(0) { $0 + $1.size } + downloads.reduce(0) { $0 + $1.size }
        let unused = apps.filter { $0.lastUsed.map { Date().timeIntervalSince($0) > 90 * 86_400 } ?? true }.count
        return [
            CareFeature(icon: "icon-cleanup", symbol: "sparkles", title: "Junk Cleanup", value: Bytes.format(selectedBytes), color: Color(0.25, 0.85, 0.75)),
            CareFeature(icon: "icon-files", symbol: "doc.fill", title: "Large & Old Files", value: Bytes.format(large), color: Color(1.0, 0.45, 0.75)),
            CareFeature(icon: "icon-projects", symbol: "hammer.fill", title: "Project Junk", value: Bytes.format(projects.reduce(0) { $0 + $1.size }), color: Color(1.0, 0.70, 0.30)),
            CareFeature(icon: "icon-apps", symbol: "square.grid.2x2.fill", title: "Unused Apps", value: "\(unused) apps", color: Color(0.70, 0.55, 1.0)),
        ]
    }

    var careSubtitle: String { "One scan finds junk, forgotten big files and idle project folders." }
}

/// Glossy sphere with a tick ring inside, like a 3D rendered hero object.
struct GlassOrb: View {
    var size: CGFloat
    var tint: Color
    var progress: Double = 0.72
    var symbol: String? = nil

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.55)).blur(radius: size * 0.16).offset(y: size * 0.1).scaleEffect(0.9)
            Circle().fill(RadialGradient(colors: [tint.mix(.white, 0.55), tint, tint.mix(.black, 0.45)],
                                         center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: size * 0.75))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.05), .white.opacity(0.25)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: size * 0.018)
            Circle().fill(RadialGradient(colors: [tint.mix(.black, 0.55), tint.mix(.black, 0.25)],
                                         center: .center, startRadius: 0, endRadius: size * 0.3))
                .frame(width: size * 0.62, height: size * 0.62)
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            TickRing(progress: progress, colors: (.white, tint.mix(.white, 0.6)), ticks: 44,
                     tickLength: size * 0.05, tickWidth: max(size * 0.012, 1.5))
                .frame(width: size * 0.56, height: size * 0.56)
            if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.16, weight: .semibold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            }
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.66, height: size * 0.32).offset(y: -size * 0.3).blur(radius: 1.5)
        }
        .frame(width: size, height: size)
    }
}

/// Glossy rounded square with a symbol, like a big 3D app icon.
struct GlassTile: View {
    var size: CGFloat
    var tint: Color
    var symbol: String
    var corner: CGFloat = 0.27

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * corner, style: .continuous)
        ZStack {
            shape.fill(tint.opacity(0.5)).blur(radius: size * 0.14).offset(y: size * 0.12).scaleEffect(0.86)
            shape.fill(LinearGradient(colors: [tint.mix(.white, 0.45), tint, tint.mix(.black, 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                               lineWidth: size * 0.016)
            Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                .shadow(color: tint.mix(.black, 0.5).opacity(0.5), radius: size * 0.04, y: size * 0.03)
            shape.fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                .padding(size * 0.03)
        }
        .frame(width: size, height: size)
    }
}

/// Glossy hexagon with a symbol.
struct GlassHex: View {
    var size: CGFloat
    var tint: Color
    var symbol: String

    struct Hex: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 - .pi / 6
                let pt = CGPoint(x: rect.midX + rect.width / 2 * cos(a), y: rect.midY + rect.height / 2 * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        }
    }

    var body: some View {
        ZStack {
            Hex().fill(tint.opacity(0.5)).blur(radius: size * 0.14).offset(y: size * 0.1)
            Hex().fill(LinearGradient(colors: [tint.mix(.white, 0.4), tint, tint.mix(.black, 0.4)], startPoint: .top, endPoint: .bottom))
            Hex().stroke(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: size * 0.014)
            Image(systemName: symbol).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
        }
        .frame(width: size, height: size)
    }
}

/// Round glowing button, like CleanMyMac's Scan.
struct RoundScanButton: View {
    var title = "Scan"
    var tint: Color
    var size: CGFloat = 104
    var text: Color = .white

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.6)).blur(radius: 26).frame(width: size * 1.25, height: size * 1.25)
            Circle().fill(RadialGradient(colors: [tint.mix(.white, 0.35), tint, tint.mix(.black, 0.25)],
                                         center: UnitPoint(x: 0.4, y: 0.25), startRadius: 0, endRadius: size * 0.7))
            Circle().strokeBorder(.white.opacity(0.75), lineWidth: 2.5)
            Text(title).font(.system(size: size * 0.19, weight: .semibold)).foregroundStyle(text)
        }
        .frame(width: size, height: size)
    }
}

/// Small glossy icon used in feature lists.
struct GlossyChip: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [tint.mix(.white, 0.35), tint.mix(.black, 0.15)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.4), radius: 4, y: 2)
    }
}

struct CareNav: Identifiable {
    let icon: String
    let symbol: String
    let title: String
    let color: Color
    var id: String { title }

    static let main: [CareNav] = [
        CareNav(icon: "icon-smartcare", symbol: "sparkles.rectangle.stack.fill", title: "Smart Care", color: Color(0.45, 0.6, 1.0)),
        CareNav(icon: "icon-cleanup", symbol: "sparkles", title: "Cleanup", color: Color(0.25, 0.85, 0.6)),
        CareNav(icon: "icon-lens", symbol: "chart.pie.fill", title: "Space Lens", color: Color(0.4, 0.7, 1.0)),
        CareNav(icon: "icon-files", symbol: "doc.fill", title: "Large & Old Files", color: Color(1.0, 0.45, 0.75)),
        CareNav(icon: "icon-projects", symbol: "hammer.fill", title: "Project Junk", color: Color(1.0, 0.7, 0.3)),
        CareNav(icon: "icon-apps", symbol: "square.grid.2x2.fill", title: "Uninstaller", color: Color(0.7, 0.55, 1.0)),
    ]
    static let bottom: [CareNav] = [
        CareNav(icon: "icon-activity", symbol: "chart.line.uptrend.xyaxis", title: "Activity", color: Color(0.5, 0.8, 1.0)),
        CareNav(icon: "icon-settings", symbol: "gearshape.fill", title: "Settings", color: Color(0.7, 0.7, 0.75)),
    ]
}

/// CleanMyMac-style sidebar: glossy icons with labels, a soft highlight on the selected item.
struct CareSidebar: View {
    var width: CGFloat = 232
    var dark = true
    var glossy = true
    var selected = "Smart Care"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer().frame(height: 52)
            ForEach(CareNav.main) { item in navRow(item) }
            Spacer()
            ForEach(CareNav.bottom) { item in navRow(item) }
            Spacer().frame(height: 14)
        }
        .padding(.horizontal, 14)
        .frame(width: width)
        .frame(maxHeight: .infinity)
    }

    private func navRow(_ item: CareNav) -> some View {
        let on = item.title == selected
        let text: Color = dark ? .white : Color(0.12, 0.13, 0.2)
        return HStack(spacing: 11) {
            if glossy {
                Icon3D(name: item.icon, symbol: item.symbol, tint: item.color, size: 26)
            } else {
                Image(systemName: item.symbol).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? text : text.opacity(0.55)).frame(width: 24)
            }
            Text(item.title).font(.system(size: 13, weight: on ? .semibold : .medium)).foregroundStyle(on ? text : text.opacity(0.78))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(on ? (dark ? Color.white.opacity(0.16) : Color.black.opacity(0.06)) : .clear))
    }
}

/// Top right: free space pill and the alerts bell.
struct CareToolbar: View {
    @ObservedObject var model: AppModel
    var dark = true

    var body: some View {
        let text: Color = dark ? .white : Color(0.12, 0.13, 0.2)
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive.fill").font(.system(size: 12))
                Text("\(Bytes.format(model.disk?.available ?? 0)) free").font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(text)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)))
            Image(systemName: "bell.fill").font(.system(size: 12)).foregroundStyle(text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)))
        }
        .padding(.top, 14).padding(.trailing, 16)
    }
}

private func featureRow(_ f: CareFeature, text: Color = .white, showValue: Bool = true) -> some View {
    HStack(spacing: 13) {
        Icon3D(name: f.icon, symbol: f.symbol, tint: f.color, size: 32)
        Text(f.title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(text)
        if showValue {
            Spacer(minLength: 12)
            Text(f.value).font(Theme.number(14, .semibold)).foregroundStyle(text.opacity(0.75))
        }
    }
}

// MARK: 1. Classic Care

struct ClassicCare: View {
    @ObservedObject var model: AppModel
    let tint = Color(0.32, 0.42, 1.0)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(0.22, 0.30, 0.92), Color(0.16, 0.10, 0.52)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(0.55, 0.45, 1.0).opacity(0.45), .clear], center: UnitPoint(x: 0.75, y: 0.15), startRadius: 0, endRadius: 520)
            HStack(spacing: 0) {
                CareSidebar().background(Color.black.opacity(0.12))
                    .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
                HStack(spacing: 46) {
                    HeroArt(name: "disc-care", size: 340, glow: Color(0.45, 0.45, 1.0))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Smart Care").font(.system(size: 44, weight: .medium)).foregroundStyle(.white)
                        Text(model.careSubtitle).font(.system(size: 16)).foregroundStyle(.white.opacity(0.75)).frame(width: 330, alignment: .leading)
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(model.careFeatures) { featureRow($0, showValue: false) }
                        }
                        .padding(.top, 12)
                    }
                }
                .offset(y: -30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack { Spacer(); RoundScanButton(tint: Color(0.40, 0.45, 1.0)).padding(.bottom, 26) }.padding(.leading, 232)
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model) }
    }
}

// MARK: 2. Aurora

struct AuroraCare: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color(0.03, 0.04, 0.12)
            Circle().fill(Color(0.1, 0.7, 0.95)).frame(width: 520).blur(radius: 140).offset(x: -260, y: -260)
            Circle().fill(Color(0.55, 0.25, 0.95)).frame(width: 560).blur(radius: 150).offset(x: 360, y: -60)
            Circle().fill(Color(0.95, 0.3, 0.6)).frame(width: 420).blur(radius: 150).offset(x: 80, y: 380)
            HStack(spacing: 0) {
                CareSidebar(glossy: false).background(.white.opacity(0.05))
                VStack(spacing: 18) {
                    HeroArt(name: "hero-2-aurora", size: 250, glow: Color(0.5, 0.5, 1.0))
                    Text("Smart Care").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
                    Text(model.careSubtitle).font(.system(size: 15)).foregroundStyle(.white.opacity(0.72))
                    HStack(spacing: 10) {
                        ForEach(model.careFeatures) { f in
                            HStack(spacing: 8) {
                                Image(systemName: f.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(f.color)
                                Text(f.value).font(Theme.number(13, .semibold)).foregroundStyle(.white)
                                Text(f.title).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .background(Capsule().fill(.white.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                        }
                    }
                    .padding(.top, 6)
                    Text("Scan").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 220, height: 50)
                        .background(Capsule().fill(LinearGradient(colors: [Color(0.2, 0.75, 1.0), Color(0.6, 0.35, 1.0)], startPoint: .leading, endPoint: .trailing)))
                        .shadow(color: Color(0.45, 0.5, 1.0).opacity(0.6), radius: 20, y: 6)
                        .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model) }
    }
}

// MARK: 3. Split Hero

struct SplitCare: View {
    @ObservedObject var model: AppModel
    let tint = Color(0.1, 0.7, 0.8)

    var body: some View {
        ZStack {
            Color(0.05, 0.08, 0.13)
            HStack(spacing: 0) {
                CareSidebar(glossy: false)
                HStack(spacing: 34) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(LinearGradient(colors: [Color(0.1, 0.75, 0.8), Color(0.08, 0.3, 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        RadialGradient(colors: [.white.opacity(0.25), .clear], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        VStack(spacing: 22) {
                            HeroArt(name: "hero-3-split", size: 300, glow: Color(0.2, 0.9, 1.0))
                            Text("Last scan \(model.scan.map { PanelView.relative($0.date) } ?? "never")")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(width: 400)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Smart Care").font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
                        Text(model.careSubtitle).font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
                        VStack(spacing: 0) {
                            ForEach(Array(model.careFeatures.enumerated()), id: \.offset) { i, f in
                                featureRow(f).padding(.horizontal, 16).padding(.vertical, 13)
                                if i < 3 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.leading, 59) }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
                        .padding(.top, 6)
                        HStack { Spacer(); RoundScanButton(tint: tint, size: 96) }.padding(.top, 16)
                    }
                }
                .padding(.vertical, 56).padding(.horizontal, 34)
            }
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model) }
    }
}

// MARK: 4. Glass Cards

struct GlassCardsCare: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(0.07, 0.10, 0.24), Color(0.02, 0.03, 0.09)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(0.3, 0.4, 1.0).opacity(0.35), .clear], center: UnitPoint(x: 0.6, y: 0.3), startRadius: 0, endRadius: 420)
            HStack(spacing: 0) {
                CareSidebar().background(.white.opacity(0.03))
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Smart Care").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
                            Text(model.careSubtitle).font(.system(size: 15)).foregroundStyle(.white.opacity(0.7)).frame(width: 360, alignment: .leading)
                        }
                        Spacer()
                        HeroArt(name: "hero-4-cards", size: 220, glow: Color(0.3, 0.5, 1.0))
                    }
                    HStack(spacing: 14) {
                        ForEach(model.careFeatures) { f in
                            VStack(alignment: .leading, spacing: 14) {
                                Icon3D(name: f.icon, symbol: f.symbol, tint: f.color, size: 44)
                                Spacer(minLength: 0)
                                Text(f.value).font(Theme.number(24)).foregroundStyle(.white)
                                Text(f.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                            }
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading).frame(height: 170)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.06))
                                    .overlay(alignment: .top) {
                                        RadialGradient(colors: [f.color.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 160)
                                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    })
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.1)))
                        }
                    }
                    HStack { Spacer(); RoundScanButton(tint: Color(0.35, 0.5, 1.0), size: 100); Spacer() }.padding(.top, 8)
                }
                .padding(.horizontal, 36).padding(.top, 70).padding(.bottom, 30)
            }
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model) }
    }
}

// MARK: 5. Orbit

struct OrbitCare: View {
    @ObservedObject var model: AppModel
    let tint = Color(0.6, 0.3, 1.0)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(0.36, 0.13, 0.66), Color(0.12, 0.04, 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                CareSidebar().background(Color.black.opacity(0.14))
                ZStack {
                    Circle().strokeBorder(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6])).frame(width: 470, height: 470)
                    Circle().strokeBorder(.white.opacity(0.07), lineWidth: 1).frame(width: 610, height: 610)
                    ZStack {
                        HeroArt(name: "hero-5-orbit", size: 330, glow: Color(0.65, 0.35, 1.0))
                        VStack(spacing: 2) {
                            Text("Scan").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.4), radius: 6)
                            Text(Bytes.format(model.selectedBytes) + " ready").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    ForEach(Array(model.careFeatures.enumerated()), id: \.offset) { i, f in
                        let angle = Double(i) * .pi / 2 - .pi / 4
                        HStack(spacing: 10) {
                            Icon3D(name: f.icon, symbol: f.symbol, tint: f.color, size: 42)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.value).font(Theme.number(15)).foregroundStyle(.white)
                                Text(f.title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Capsule().fill(.white.opacity(0.1)))
                        .offset(x: cos(angle) * 300, y: sin(angle) * 235)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Smart Care").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        Text(model.careSubtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)).frame(width: 260, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 34).padding(.top, 60)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model) }
    }
}

// MARK: 6. Monochrome Pro

struct MonoCare: View {
    @ObservedObject var model: AppModel
    let accent = Color(0.35, 0.85, 1.0)

    var body: some View {
        ZStack {
            Color(0.055, 0.06, 0.07)
            HStack(spacing: 0) {
                CareSidebar(glossy: false).background(.white.opacity(0.025))
                    .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1) }
                HStack(spacing: 56) {
                    VStack(spacing: 6) {
                        HeroArt(name: "hero-6-mono", size: 300, glow: accent.opacity(0.6))
                        Text(Bytes.format(model.disk?.available ?? 0)).font(.system(size: 32, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                        Text("AVAILABLE").font(.system(size: 10.5, weight: .semibold)).tracking(2).foregroundStyle(.white.opacity(0.45))
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Smart Care").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                        Text(model.careSubtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.55)).frame(width: 320, alignment: .leading)
                        VStack(spacing: 0) {
                            ForEach(model.careFeatures) { f in
                                HStack {
                                    Image(systemName: f.symbol).font(.system(size: 12)).foregroundStyle(accent).frame(width: 20)
                                    Text(f.title).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.85))
                                    Spacer()
                                    Text(f.value).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(.white)
                                }
                                .padding(.vertical, 11)
                                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
                            }
                        }
                        .frame(width: 340)
                        Text("Scan").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                            .frame(width: 96, height: 96)
                            .overlay(Circle().strokeBorder(accent, lineWidth: 2))
                            .shadow(color: accent.opacity(0.6), radius: 14)
                            .padding(.top, 14)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model) }
    }
}

// MARK: 7. Bento Care

struct BentoCare: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color(0.07, 0.08, 0.12)
            HStack(spacing: 0) {
                CareSidebar()
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        ZStack(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(LinearGradient(colors: [Color(0.25, 0.35, 0.95), Color(0.35, 0.15, 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            HeroArt(name: "hero-7-bento", size: 290, glow: Color(0.4, 0.5, 1.0))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(20)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Smart Care").font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
                                Text(model.careSubtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8)).frame(width: 280, alignment: .leading)
                                Text("Scan").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(0.2, 0.25, 0.7))
                                    .frame(width: 140, height: 44).background(Capsule().fill(.white)).padding(.top, 8)
                            }
                            .padding(26)
                        }
                        VStack(spacing: 14) {
                            ForEach(model.careFeatures.prefix(2)) { tile($0) }
                        }
                        .frame(width: 250)
                    }
                    .frame(height: 420)
                    HStack(spacing: 14) {
                        ForEach(model.careFeatures.suffix(2)) { tile($0) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Available").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                            Text(Bytes.format(model.disk?.available ?? 0)).font(Theme.number(28)).foregroundStyle(.white)
                            CapacityBar(fraction: model.disk?.usedFraction ?? 0, color: Color(0.45, 0.9, 0.55), height: 6)
                        }
                        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 22).padding(.top, 60).padding(.bottom, 22)
            }
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model) }
    }

    private func tile(_ f: CareFeature) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Icon3D(name: f.icon, symbol: f.symbol, tint: f.color, size: 42)
            Spacer(minLength: 0)
            Text(f.value).font(Theme.number(24)).foregroundStyle(.white)
            Text(f.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [f.color.opacity(0.32), f.color.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(f.color.opacity(0.3)))
    }
}

// MARK: 8. Floating Sidebar

struct FloatingCare: View {
    @ObservedObject var model: AppModel
    let tint = Color(0.15, 0.75, 0.45)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(0.06, 0.50, 0.32), Color(0.02, 0.17, 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(0.4, 0.95, 0.6).opacity(0.35), .clear], center: UnitPoint(x: 0.72, y: 0.45), startRadius: 0, endRadius: 380)
            HStack(spacing: 0) {
                CareSidebar(selected: "Smart Care")
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.09)))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
                    .padding(12)
                HStack(spacing: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Smart Care").font(.system(size: 44, weight: .medium)).foregroundStyle(.white)
                        Text(model.careSubtitle).font(.system(size: 16)).foregroundStyle(.white.opacity(0.75)).frame(width: 330, alignment: .leading)
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(model.careFeatures) { featureRow($0).frame(width: 320) }
                        }
                        .padding(.top, 12)
                    }
                    ZStack {
                        HeroArt(name: "hero-8-floating", size: 330, glow: Color(0.3, 0.95, 0.5))
                    }
                }
                .offset(y: -24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack { Spacer(); RoundScanButton(tint: Color(0.2, 0.8, 0.5)).padding(.bottom, 24) }.padding(.leading, 256)
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model) }
    }
}

// MARK: 9. Steps

struct StepsCare: View {
    @ObservedObject var model: AppModel
    let tint = Color(0.9, 0.25, 0.6)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(0.58, 0.10, 0.42), Color(0.22, 0.03, 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(1.0, 0.45, 0.75).opacity(0.3), .clear], center: UnitPoint(x: 0.6, y: 0.2), startRadius: 0, endRadius: 420)
            HStack(spacing: 0) {
                CareSidebar().background(Color.black.opacity(0.12))
                VStack(spacing: 18) {
                    HeroArt(name: "hero-9-steps", size: 190, glow: Color(1.0, 0.4, 0.7))
                    VStack(spacing: 6) {
                        Text("Smart Care").font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
                        Text(model.careSubtitle).font(.system(size: 14.5)).foregroundStyle(.white.opacity(0.75))
                    }
                    HStack(spacing: 0) {
                        step(1, "Scan", "Find what's removable", active: true)
                        connector
                        step(2, "Review", "Untick what you keep", active: false)
                        connector
                        step(3, "Clean", "Free the space", active: false)
                    }
                    .padding(.vertical, 6)
                    LazyVGrid(columns: [GridItem(.fixed(270), spacing: 18), GridItem(.fixed(270))], spacing: 12) {
                        ForEach(model.careFeatures) { featureRow($0) }
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.07)))
                    RoundScanButton(tint: Color(0.95, 0.35, 0.65), size: 92)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 20)
            }
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model) }
    }

    private var connector: some View {
        Rectangle().fill(.white.opacity(0.25)).frame(width: 60, height: 2).padding(.bottom, 30)
    }

    private func step(_ n: Int, _ title: String, _ detail: String, active: Bool) -> some View {
        VStack(spacing: 6) {
            Text("\(n)").font(Theme.number(14, .bold)).foregroundStyle(active ? Color(0.55, 0.08, 0.4) : .white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(active ? Color.white : Color.white.opacity(0.15)))
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 130)
    }
}

// MARK: 10. Light Fresh

struct LightCare: View {
    @ObservedObject var model: AppModel
    let ink = Color(0.11, 0.12, 0.2)
    let tint = Color(0.25, 0.5, 1.0)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(0.97, 0.97, 1.0), Color(0.90, 0.92, 0.99)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(0.55, 0.7, 1.0).opacity(0.45)).frame(width: 520).blur(radius: 120).offset(x: 330, y: -230)
            Circle().fill(Color(0.85, 0.65, 1.0).opacity(0.35)).frame(width: 420).blur(radius: 120).offset(x: -120, y: 320)
            HStack(spacing: 0) {
                CareSidebar(dark: false).background(.white.opacity(0.55))
                    .overlay(alignment: .trailing) { Rectangle().fill(Color.black.opacity(0.06)).frame(width: 1) }
                HStack(spacing: 46) {
                    HeroArt(name: "hero-10-light", size: 300, glow: Color(0.45, 0.65, 1.0))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Smart Care").font(.system(size: 42, weight: .semibold)).foregroundStyle(ink)
                        Text(model.careSubtitle).font(.system(size: 15.5)).foregroundStyle(ink.opacity(0.6)).frame(width: 330, alignment: .leading)
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(model.careFeatures) { featureRow($0, text: ink).frame(width: 320) }
                        }
                        .padding(.top, 10)
                    }
                }
                .offset(y: -30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack { Spacer(); RoundScanButton(tint: tint).padding(.bottom, 26) }.padding(.leading, 232)
        }
        .overlay(alignment: .topTrailing) { CareToolbar(model: model, dark: false) }
    }
}
