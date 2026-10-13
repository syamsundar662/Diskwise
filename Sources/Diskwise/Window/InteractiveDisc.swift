import AppKit
import ImageIO
import QuartzCore
import SwiftUI
import DiskwiseCore

// The Blender disc turned toward the cursor, drawn with Core Animation so it stays
// smooth: frames are decoded once, a display link eases toward the cursor, and
// mouse movement never re-renders the SwiftUI page around it.

/// The 7 x 5 grid of Blender renders (yaw -15...15, pitch -10...10), decoded once.
final class DiscFrames {
    static let shared = DiscFrames()
    static let yaws: [Double] = [-15, -10, -5, 0, 5, 10, 15]
    static let pitches: [Double] = [-10, -5, 0, 5, 10]

    private(set) var images: [[CGImage?]] = []
    private(set) var ready = false
    private var waiting: [() -> Void] = []
    private let lock = NSLock()

    /// Decodes every frame in the background; `then` runs on the main thread when done.
    func load(then: (() -> Void)? = nil) {
        lock.lock()
        if ready {
            lock.unlock()
            if let then { DispatchQueue.main.async(execute: then) }
            return
        }
        let first = waiting.isEmpty
        if let then { waiting.append(then) }
        lock.unlock()
        guard first || then == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let grid = Self.yaws.indices.map { yi in
                Self.pitches.indices.map { pi in Self.decode(Art.url("disc-tilt-\(yi)-\(pi)")) }
            }
            DispatchQueue.main.async {
                self.lock.lock()
                self.images = grid
                self.ready = true
                let callbacks = self.waiting
                self.waiting = []
                self.lock.unlock()
                callbacks.forEach { $0() }
            }
        }
    }

    func image(_ yi: Int, _ pi: Int) -> CGImage? {
        guard ready, images.indices.contains(yi), images[yi].indices.contains(pi) else { return nil }
        return images[yi][pi]
    }

    static func decode(_ url: URL?) -> CGImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// Connects the page's cursor tracking to the layer views without touching SwiftUI state.
final class DiscMotion {
    weak var disc: DiscLayerView?
    weak var light: PointerLightView?

    /// `point` in the page's coordinates (top left origin), nil when the cursor leaves.
    func pointer(_ point: CGPoint?, heroCenter: CGPoint) {
        light?.move(to: point)
        guard let point else {
            disc?.setTarget(.zero)
            return
        }
        disc?.setTarget(CGSize(width: max(-1, min(1, (point.x - heroCenter.x) / 420)),
                               height: max(-1, min(1, (heroCenter.y - point.y) / 320))))
    }
}

struct DiscView: NSViewRepresentable {
    let motion: DiscMotion
    var scanning: Bool
    /// Changes when a scan finishes, to play the spin once.
    var celebrations: Int
    var bounces: Int

    func makeNSView(context: Context) -> DiscLayerView {
        let view = DiscLayerView()
        motion.disc = view
        return view
    }

    func updateNSView(_ view: DiscLayerView, context: Context) {
        motion.disc = view
        view.scanning = scanning
        if celebrations != view.celebrations {
            view.celebrations = celebrations
            if celebrations > 0 { view.celebrate() }
        }
        if bounces != view.bounces {
            view.bounces = bounces
            view.bounce()
        }
    }
}

final class DiscLayerView: NSView {
    private let container = CALayer()
    private let imageLayer = CALayer()
    private let beam = CAGradientLayer()
    private let beamMask = CALayer()
    private var link: CADisplayLink?
    private var target = CGSize.zero
    private var current = CGSize.zero
    private var velocity = CGSize.zero
    private var frame3 = (-1, -1)
    private var celebrationStart: CFTimeInterval?
    var celebrations = 0
    var bounces = 0

    static let celebration: CFTimeInterval = 1.4

    var scanning = false {
        didSet {
            guard scanning != oldValue else { return }
            beam.isHidden = !scanning
            if scanning { startBeam() } else { beam.removeAllAnimations() }
            run()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        container.masksToBounds = false
        imageLayer.contentsGravity = .resizeAspect
        beamMask.contentsGravity = .resizeAspect
        beam.colors = [NSColor.clear.cgColor, NSColor.white.withAlphaComponent(0.5).cgColor, NSColor.clear.cgColor]
        beam.startPoint = CGPoint(x: 0, y: 0.5)
        beam.endPoint = CGPoint(x: 1, y: 0.5)
        beam.compositingFilter = "plusL"
        beam.isHidden = true
        let beamHolder = CALayer()
        beamHolder.mask = beamMask
        beamHolder.addSublayer(beam)
        container.addSublayer(imageLayer)
        container.addSublayer(beamHolder)
        layer?.addSublayer(container)
        imageLayer.contents = Art.image("disc-care")
        DiscFrames.shared.load { [weak self] in
            self?.frame3 = (-1, -1)
            self?.render(time: CACurrentMediaTime())
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Clicks and hovers go to the SwiftUI page, which forwards them here.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        imageLayer.frame = container.bounds
        if let holder = beam.superlayer {
            holder.frame = container.bounds
            beamMask.frame = holder.bounds
            beam.frame = CGRect(x: -bounds.width * 0.5, y: -bounds.height * 0.3, width: bounds.width * 0.35, height: bounds.height * 1.6)
            beam.setAffineTransform(CGAffineTransform(rotationAngle: -0.35))
        }
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (max(bounds.width, 1) * 2.6)
        container.sublayerTransform = perspective
        CATransaction.commit()
        render(time: CACurrentMediaTime())
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            link?.invalidate()
            link = nil
        } else {
            run()
        }
    }

    func setTarget(_ value: CGSize) {
        target = value
        run()
    }

    func celebrate() {
        celebrationStart = CACurrentMediaTime()
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [1, 1.08, 0.98, 1]
        pop.keyTimes = [0, 0.35, 0.7, 1]
        pop.duration = 0.7
        pop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeOut)]
        container.add(pop, forKey: "pop")
        run()
    }

    func bounce() {
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.9
        spring.toValue = 1
        spring.damping = 9
        spring.stiffness = 260
        spring.initialVelocity = -4
        spring.duration = spring.settlingDuration
        container.add(spring, forKey: "bounce")
    }

    private func startBeam() {
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -bounds.width * 0.2
        sweep.toValue = bounds.width * 1.2
        sweep.duration = 2.0
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        beam.add(sweep, forKey: "sweep")
    }

    private func run() {
        guard window != nil else { return }
        if link == nil {
            link = displayLink(target: self, selector: #selector(tick(_:)))
            link?.add(to: .main, forMode: .common)
        }
        link?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(max(link.targetTimestamp - link.timestamp, 1.0 / 240), 1.0 / 30)
        // Spring toward the cursor: quick, without wobble.
        let stiffness = 90.0, damping = 2 * sqrt(stiffness) * 0.9
        let ax = stiffness * (target.width - current.width) - damping * velocity.width
        let ay = stiffness * (target.height - current.height) - damping * velocity.height
        velocity.width += ax * dt
        velocity.height += ay * dt
        current.width += velocity.width * dt
        current.height += velocity.height * dt
        render(time: link.targetTimestamp)

        let settled = abs(target.width - current.width) < 0.001 && abs(target.height - current.height) < 0.001
            && abs(velocity.width) < 0.001 && abs(velocity.height) < 0.001
        let celebrating = celebrationStart.map { link.targetTimestamp - $0 < Self.celebration } ?? false
        if settled && !scanning && !celebrating {
            current = target
            velocity = .zero
            celebrationStart = nil
            link.isPaused = true
        }
    }

    private func render(time: CFTimeInterval) {
        var yaw = Double(current.width) * 15
        var pitch = Double(current.height) * 10
        if scanning {
            yaw = yaw * 0.4 + 12 * sin(time * 1.7)
            pitch = pitch * 0.4 + 4 * sin(time * 1.1)
        }
        if let start = celebrationStart {
            let p = (time - start) / Self.celebration
            if p >= 0, p < 1 { yaw += 15 * sin(p * 2 * .pi) * (1 - p) }
        }
        let yaws = DiscFrames.yaws, pitches = DiscFrames.pitches
        let yi = Self.nearest(min(max(yaw, yaws.first!), yaws.last!), in: yaws)
        let pi = Self.nearest(min(max(pitch, pitches.first!), pitches.last!), in: pitches)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frame3 != (yi, pi), let image = DiscFrames.shared.image(yi, pi) {
            frame3 = (yi, pi)
            imageLayer.contents = image
            beamMask.contents = image
        }
        let residualYaw = (yaw - yaws[yi]) * .pi / 180
        let residualPitch = (pitch - pitches[pi]) * .pi / 180
        var transform = CATransform3DMakeRotation(CGFloat(residualYaw), 0, 1, 0)
        transform = CATransform3DRotate(transform, CGFloat(-residualPitch), 1, 0, 0)
        imageLayer.transform = transform
        beam.superlayer?.transform = transform
        CATransaction.commit()
    }

    private static func nearest(_ value: Double, in steps: [Double]) -> Int {
        steps.indices.min { abs(steps[$0] - value) < abs(steps[$1] - value) } ?? 0
    }
}

/// A soft light that follows the cursor across the page: a gradient layer moved by
/// Core Animation, no blur.
struct PointerLight: NSViewRepresentable {
    let motion: DiscMotion
    let color: Color

    func makeNSView(context: Context) -> PointerLightView {
        let view = PointerLightView(color: NSColor(color))
        motion.light = view
        return view
    }

    func updateNSView(_ view: PointerLightView, context: Context) { motion.light = view }
}

final class PointerLightView: NSView {
    private let light = CAGradientLayer()

    init(color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        light.type = .radial
        light.colors = [color.withAlphaComponent(0.26).cgColor, color.withAlphaComponent(0.08).cgColor, NSColor.clear.cgColor]
        light.locations = [0, 0.45, 1]
        light.startPoint = CGPoint(x: 0.5, y: 0.5)
        light.endPoint = CGPoint(x: 1, y: 1)
        light.bounds = CGRect(x: 0, y: 0, width: 560, height: 560)
        light.opacity = 0
        layer?.addSublayer(light)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Let clicks and hovers through to the page.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func move(to point: CGPoint?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        if let point {
            if light.opacity == 0 {
                CATransaction.setDisableActions(true)
                light.position = CGPoint(x: point.x, y: bounds.height - point.y)
                CATransaction.setDisableActions(false)
            }
            light.position = CGPoint(x: point.x, y: bounds.height - point.y)
            light.opacity = 1
        } else {
            light.opacity = 0
        }
        CATransaction.commit()
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
        .opacity(trigger == 0 ? 0 : 1)
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
            .onAppear {
                guard !RenderMode.snapshot else { return }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { turning = true }
            }
            .allowsHitTesting(false)
    }
}
