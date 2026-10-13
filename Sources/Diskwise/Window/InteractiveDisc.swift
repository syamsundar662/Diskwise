import SwiftUI
import DiskwiseCore

/// The Blender disc, turned toward the cursor. Blender rendered it from a grid of
/// angles (7 yaw x 5 pitch, 5 degrees apart); the closest render is shown and a
/// small 3D rotation covers the rest, so it turns smoothly with real reflections.
struct InteractiveDisc: View, Animatable {
    /// Where the cursor pulls the disc, -1...1 on each axis (x right, y up).
    var tilt: CGSize
    var size: CGFloat
    var glow: Color
    var scanning: Bool
    /// When the last scan finished; drives the one-time celebration spin.
    var celebratedAt: Date?

    static let yaws: [Double] = [-15, -10, -5, 0, 5, 10, 15]
    static let pitches: [Double] = [-10, -5, 0, 5, 10]

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(tilt.width, tilt.height) }
        set { tilt = CGSize(width: newValue.first, height: newValue.second) }
    }

    var body: some View {
        let active = scanning || celebratedAt.map { Date().timeIntervalSince($0) < Self.celebration } ?? false
        TimelineView(.animation(minimumInterval: nil, paused: !active || RenderMode.snapshot)) { context in
            disc(at: context.date)
        }
    }

    static let celebration: TimeInterval = 1.4

    private func disc(at now: Date) -> some View {
        var yaw = Double(tilt.width) * 15
        var pitch = Double(tilt.height) * 10
        var pop: CGFloat = 1
        var flash = 0.0
        let t = now.timeIntervalSinceReferenceDate
        if scanning {
            // Sway side to side while scanning, like it is looking around.
            yaw = yaw * 0.4 + 12 * sin(t * 1.7)
            pitch = pitch * 0.4 + 4 * sin(t * 1.1)
        }
        if let start = celebratedAt {
            let p = now.timeIntervalSince(start) / Self.celebration
            if p >= 0, p < 1 {
                // One quick turn across and back, a small pop and a glow flash.
                yaw += 15 * sin(p * 2 * .pi) * (1 - p)
                pop = 1 + 0.07 * CGFloat(sin(min(p * 2, 1) * .pi))
                flash = sin(p * .pi)
            }
        }
        let clampedYaw = min(max(yaw, Self.yaws.first!), Self.yaws.last!)
        let clampedPitch = min(max(pitch, Self.pitches.first!), Self.pitches.last!)
        let yi = Self.nearest(clampedYaw, in: Self.yaws)
        let pi = Self.nearest(clampedPitch, in: Self.pitches)
        let residualYaw = yaw - Self.yaws[yi]
        let residualPitch = pitch - Self.pitches[pi]

        return ZStack {
            Ellipse().fill(glow.opacity(0.5)).frame(width: size * 0.78, height: size * 0.2)
                .blur(radius: size * 0.09)
                .offset(x: -CGFloat(yaw) * 1.6, y: size * 0.44)
            Circle().fill(glow.opacity(0.24 + (scanning ? 0.14 : 0) + flash * 0.3)).frame(width: size * 0.9)
                .blur(radius: size * 0.16)
                .offset(x: CGFloat(yaw) * 0.8, y: -CGFloat(pitch) * 0.8)
            if let image = Art.image("disc-tilt-\(yi)-\(pi)") ?? Art.image("disc-care") {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .overlay {
                        if scanning { ScanBeam(time: t).mask(Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)) }
                    }
                    .rotation3DEffect(.degrees(residualYaw), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                    .rotation3DEffect(.degrees(residualPitch), axis: (x: -1, y: 0, z: 0), perspective: 0.4)
                    .scaleEffect(pop)
            }
        }
        .frame(width: size, height: size)
    }

    private static func nearest(_ value: Double, in steps: [Double]) -> Int {
        steps.indices.min { abs(steps[$0] - value) < abs(steps[$1] - value) } ?? 0
    }
}

/// A soft band of light sweeping across the disc while it scans.
private struct ScanBeam: View {
    let time: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let phase = (time.truncatingRemainder(dividingBy: 2.2)) / 2.2
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.35)
                .rotationEffect(.degrees(20))
                .offset(x: geo.size.width * (CGFloat(phase) * 1.7 - 0.5))
                .blendMode(.plusLighter)
        }
    }
}

/// Rings that pulse out from the Scan button when it is pressed.
struct RippleRings: View {
    let tint: Color
    let trigger: Int
    @State private var expand = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle().strokeBorder(tint.mix(.white, 0.4), lineWidth: 2)
                    .scaleEffect(expand ? 2.6 : 1)
                    .opacity(expand ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.1).delay(Double(i) * 0.16), value: expand)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            expand = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { expand = true }
        }
    }
}

/// Sparkles that burst out of the disc when a scan finishes, then a checkmark.
struct CompletionBurst: View {
    let tint: Color
    let trigger: Int
    @State private var burst = false
    @State private var showCheck = false

    var body: some View {
        ZStack {
            ForEach(0..<10) { i in
                let angle = Double(i) / 10 * 2 * .pi + 0.3
                Image(systemName: i % 2 == 0 ? "sparkle" : "circle.fill")
                    .font(.system(size: i % 2 == 0 ? 16 : 6, weight: .bold))
                    .foregroundStyle(i % 3 == 0 ? .white : tint.mix(.white, 0.5))
                    .offset(x: burst ? cos(angle) * 210 : 0, y: burst ? sin(angle) * 190 : 0)
                    .scaleEffect(burst ? 0.4 : 1.2)
                    .opacity(burst ? 0 : 1)
            }
            if showCheck {
                DrawnCheckmark()
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.raised.opacity(0.85)))
                    .shadow(color: Theme.green.opacity(0.6), radius: 12)
                    .offset(x: 120, y: -110)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .opacity(trigger == 0 ? 0 : 1)
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            burst = false
            withAnimation(.easeOut(duration: 1.0)) { burst = true }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.25)) { showCheck = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation(.easeOut(duration: 0.4)) { showCheck = false }
            }
        }
    }
}

/// A light that circles the disc while scanning.
struct OrbitLight: View {
    let glow: Color
    let size: CGFloat
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(AngularGradient(colors: [glow.opacity(0), glow, .white], center: .center),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: size * 1.08, height: size * 1.08)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .blur(radius: 0.6)
            .onAppear {
                guard !RenderMode.snapshot else { return }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { turning = true }
            }
            .allowsHitTesting(false)
    }
}
