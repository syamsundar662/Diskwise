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
    private let floater = CALayer()
    private let container = CALayer()
    private let imageLayer = CALayer()
    private let beam = CAGradientLayer()
    private let beamMask = CALayer()
    private let orbit = CAGradientLayer()
    private let orbitRing = CAShapeLayer()
    private var link: CADisplayLink?
    private var target = CGSize.zero
    private var current = CGSize.zero
    private var velocity = CGSize.zero
    private var frame3 = (-1, -1)
    var celebrations = 0
    var bounces = 0

    static let celebration: CFTimeInterval = 1.4

    var scanning = false {
        didSet {
            guard scanning != oldValue else { return }
            beam.isHidden = !scanning
            if scanning {
                startBeam()
                startSway()
                showOrbit(true)
                link?.isPaused = true
            } else {
                beam.removeAllAnimations()
                stopSway()
                showOrbit(false)
                frame3 = (-1, -1)
                render(time: CACurrentMediaTime())
                run()
            }
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
        floater.addSublayer(container)
        // The light that circles the disc while scanning: a conic gradient seen through a ring.
        orbit.type = .conic
        orbit.startPoint = CGPoint(x: 0.5, y: 0.5)
        orbit.endPoint = CGPoint(x: 0.5, y: 0)
        orbit.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor,
                        NSColor(red: 0.55, green: 0.5, blue: 1, alpha: 1).cgColor, NSColor.white.cgColor]
        orbit.locations = [0, 0.7, 0.93, 1]
        orbitRing.fillColor = nil
        orbitRing.strokeColor = NSColor.white.cgColor
        orbitRing.lineWidth = 4
        orbitRing.lineCap = .round
        orbit.mask = orbitRing
        orbit.opacity = 0
        layer?.addSublayer(orbit)
        layer?.addSublayer(floater)
        // A gentle idle float, run by Core Animation off the main thread.
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = -6
        float.toValue = 6
        float.duration = 3.2
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        floater.add(float, forKey: "float")
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
        floater.frame = bounds
        container.frame = floater.bounds
        imageLayer.frame = container.bounds
        if let holder = beam.superlayer {
            holder.frame = container.bounds
            beamMask.frame = holder.bounds
            beam.frame = CGRect(x: -bounds.width * 0.5, y: -bounds.height * 0.3, width: bounds.width * 0.35, height: bounds.height * 1.6)
            beam.setAffineTransform(CGAffineTransform(rotationAngle: -0.35))
        }
        let ring = bounds.insetBy(dx: -bounds.width * 0.04, dy: -bounds.height * 0.04)
        orbit.frame = ring
        orbitRing.frame = orbit.bounds
        orbitRing.path = CGPath(ellipseIn: orbit.bounds.insetBy(dx: 3, dy: 3), transform: nil)
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
        if !scanning { run() }
    }

    func celebrate() {
        // One quick turn across and back, played by Core Animation.
        playMotion(duration: Self.celebration, repeats: false, key: "celebrate") { p in
            (15 * sin(p * 2 * .pi) * (1 - p) + Double(self.current.width) * 15, Double(self.current.height) * 10)
        }
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

    /// Side to side sway while scanning, entirely in Core Animation so a busy main thread can't stutter it.
    private func startSway() {
        playMotion(duration: 4.2, repeats: true, key: "sway") { p in
            (12 * sin(p * 2 * .pi), 4 * sin(p * 4 * .pi + 0.6))
        }
    }

    private func stopSway() {
        for layer in [imageLayer, beamMask] { layer.removeAnimation(forKey: "sway-contents") }
        for layer in [imageLayer, beam.superlayer].compactMap({ $0 }) { layer.removeAnimation(forKey: "sway-transform") }
    }

    private func showOrbit(_ visible: Bool) {
        if visible {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 2.4
            spin.repeatCount = .infinity
            orbit.add(spin, forKey: "spin")
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        orbit.opacity = visible ? 1 : 0
        CATransaction.commit()
        if !visible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, !self.scanning else { return }
                self.orbit.removeAnimation(forKey: "spin")
            }
        }
    }

    /// Plays a yaw/pitch path through the Blender frames as Core Animation keyframes:
    /// the frame shown (discrete) plus the small 3D rotation between frames (smooth).
    private func playMotion(duration: CFTimeInterval, repeats: Bool, key: String, path: (Double) -> (Double, Double)) {
        guard DiscFrames.shared.ready else { return }
        let samples = Int(duration * 90)
        var images: [Any] = [], transforms: [NSValue] = [], times: [NSNumber] = []
        for i in 0...samples {
            let p = Double(i) / Double(samples)
            let (yaw, pitch) = path(p)
            let pose = Self.pose(yaw: yaw, pitch: pitch)
            guard let image = DiscFrames.shared.image(pose.yi, pose.pi) else { return }
            images.append(image)
            transforms.append(NSValue(caTransform3D: pose.transform))
            times.append(NSNumber(value: p))
        }
        let contents = CAKeyframeAnimation(keyPath: "contents")
        contents.values = images
        contents.keyTimes = times
        contents.calculationMode = .discrete
        let rotation = CAKeyframeAnimation(keyPath: "transform")
        rotation.values = transforms
        rotation.keyTimes = times
        rotation.calculationMode = .linear
        for animation in [contents, rotation] {
            animation.duration = duration
            animation.repeatCount = repeats ? .infinity : 1
            animation.isRemovedOnCompletion = true
        }
        imageLayer.add(contents, forKey: key + "-contents")
        beamMask.add(contents, forKey: key + "-contents")
        imageLayer.add(rotation, forKey: key + "-transform")
        beam.superlayer?.add(rotation, forKey: key + "-transform")
    }

    private static func pose(yaw: Double, pitch: Double) -> (yi: Int, pi: Int, transform: CATransform3D) {
        let yaws = DiscFrames.yaws, pitches = DiscFrames.pitches
        let yi = nearest(min(max(yaw, yaws.first!), yaws.last!), in: yaws)
        let pi = nearest(min(max(pitch, pitches.first!), pitches.last!), in: pitches)
        var transform = CATransform3DMakeRotation(CGFloat((yaw - yaws[yi]) * .pi / 180), 0, 1, 0)
        transform = CATransform3DRotate(transform, CGFloat(-(pitch - pitches[pi]) * .pi / 180), 1, 0, 0)
        return (yi, pi, transform)
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
        if settled || scanning {
            current = target
            velocity = .zero
            link.isPaused = true
        }
    }

    /// Shows the disc turned toward the cursor (the main-thread path; sway and spins run in Core Animation).
    private func render(time: CFTimeInterval) {
        guard !scanning else { return }
        let pose = Self.pose(yaw: Double(current.width) * 15, pitch: Double(current.height) * 10)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frame3 != (pose.yi, pose.pi), let image = DiscFrames.shared.image(pose.yi, pose.pi) {
            frame3 = (pose.yi, pose.pi)
            imageLayer.contents = image
            beamMask.contents = image
        }
        imageLayer.transform = pose.transform
        beam.superlayer?.transform = pose.transform
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
