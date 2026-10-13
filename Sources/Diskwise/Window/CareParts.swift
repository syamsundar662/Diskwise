import AppKit
import SwiftUI
import DiskwiseCore

// The 3D look of the main window: artwork from Resources/Art, the hero
// object, 3D icons and the round glowing action button.

extension Color {
    /// Blends toward another color (0 keeps this one, 1 gives the other).
    func mix(_ other: Color, _ amount: CGFloat) -> Color {
        Color(nsColor: NSColor(self).usingColorSpace(.deviceRGB)?
            .blended(withFraction: amount, of: NSColor(other).usingColorSpace(.deviceRGB) ?? .white) ?? NSColor(self))
    }

    init(_ r: Double, _ g: Double, _ b: Double) { self.init(red: r, green: g, blue: b) }
}

/// 3D artwork: from the app bundle when shipped, from the repo's Resources/Art during development.
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

/// A small 3D icon, falling back to a drawn glossy chip when its art is missing.
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

/// Small glossy icon drawn in code.
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
    }
}

/// The round glowing action button (Scan, Clean). Shows a progress ring while busy.
struct RoundActionButton: View {
    let title: String
    let tint: Color
    var progress: Double? = nil
    var size: CGFloat = 108
    let action: () -> Void
    @State private var hovering = false
    @State private var breathing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(tint.opacity(hovering ? 0.75 : 0.55)).blur(radius: 26)
                    .frame(width: size * 1.25, height: size * 1.25)
                    .scaleEffect(breathing ? 1.06 : 0.94)
                Circle().fill(RadialGradient(colors: [tint.mix(.white, 0.38), tint, tint.mix(.black, 0.28)],
                                             center: UnitPoint(x: 0.4, y: 0.25), startRadius: 0, endRadius: size * 0.7))
                Circle().strokeBorder(.white.opacity(0.75), lineWidth: 2.5)
                if let progress {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 4).padding(9)
                    Circle().trim(from: 0, to: max(progress, 0.02))
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(9)
                        .animation(.easeOut(duration: 0.4), value: progress)
                    Text("\(Int(progress * 100))%").font(.system(size: size * 0.18, weight: .semibold)).foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: progress))
                } else {
                    Text(title).font(.system(size: size * 0.19, weight: .semibold)).foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(hovering && progress == nil ? 1.05 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onAppear {
            guard !RenderMode.snapshot else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathing = true }
        }
        .disabled(progress != nil)
        .accessibilityLabel(progress == nil ? title : "Scanning, \(Int((progress ?? 0) * 100)) percent")
    }
}

/// Shrinks a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
