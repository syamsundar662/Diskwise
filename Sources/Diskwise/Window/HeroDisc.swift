import AppKit
import QuartzCore
import SwiftUI
import DiskwiseCore

// The Blender disc on the Smart Care page. One render, moved only by Core Animation
// (float, scanning sway, finishing swing), so it costs nothing on the main thread.

struct HeroDiscView: NSViewRepresentable {
    var scanning: Bool
    /// Changes when a scan finishes, to play the swing once.
    var celebrations: Int
    var bounces: Int

    func makeNSView(context: Context) -> HeroDiscLayerView { HeroDiscLayerView() }

    func updateNSView(_ view: HeroDiscLayerView, context: Context) {
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

final class HeroDiscLayerView: NSView {
    private let floater = CALayer()
    private let container = CALayer()
    private let imageLayer = CALayer()
    private let beamHolder = CALayer()
    private let beam = CAGradientLayer()
    private let beamMask = CALayer()
    private let orbit = CAGradientLayer()
    private let orbitRing = CAShapeLayer()
    var celebrations = 0
    var bounces = 0

    var scanning = false {
        didSet {
            guard scanning != oldValue else { return }
            scanning ? startScanning() : stopScanning()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        let image = Art.image("disc-care")
        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspect
        beamMask.contents = image
        beamMask.contentsGravity = .resizeAspect
        beam.colors = [NSColor.clear.cgColor, NSColor.white.withAlphaComponent(0.5).cgColor, NSColor.clear.cgColor]
        beam.startPoint = CGPoint(x: 0, y: 0.5)
        beam.endPoint = CGPoint(x: 1, y: 0.5)
        beam.compositingFilter = "plusL"
        beamHolder.mask = beamMask
        beamHolder.addSublayer(beam)
        beamHolder.isHidden = true

        orbit.type = .conic
        orbit.startPoint = CGPoint(x: 0.5, y: 0.5)
        orbit.endPoint = CGPoint(x: 0.5, y: 0)
        orbit.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor,
                        NSColor(red: 0.55, green: 0.5, blue: 1, alpha: 1).cgColor, NSColor.white.cgColor]
        orbit.locations = [0, 0.7, 0.93, 1]
        orbitRing.fillColor = nil
        orbitRing.strokeColor = NSColor.white.cgColor
        orbitRing.lineWidth = 4
        orbit.mask = orbitRing
        orbit.opacity = 0

        container.addSublayer(imageLayer)
        container.addSublayer(beamHolder)
        floater.addSublayer(container)
        layer?.addSublayer(orbit)
        layer?.addSublayer(floater)

        // A gentle idle float.
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = -6
        float.toValue = 6
        float.duration = 3.2
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        floater.add(float, forKey: "float")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Clicks go to the SwiftUI page.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        floater.frame = bounds
        container.frame = floater.bounds
        imageLayer.frame = container.bounds
        beamHolder.frame = container.bounds
        beamMask.frame = beamHolder.bounds
        beam.frame = CGRect(x: -bounds.width * 0.5, y: -bounds.height * 0.3, width: bounds.width * 0.35, height: bounds.height * 1.6)
        beam.setAffineTransform(CGAffineTransform(rotationAngle: -0.35))
        orbit.frame = bounds.insetBy(dx: -bounds.width * 0.04, dy: -bounds.height * 0.04)
        orbitRing.frame = orbit.bounds
        orbitRing.path = CGPath(ellipseIn: orbit.bounds.insetBy(dx: 3, dy: 3), transform: nil)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (max(bounds.width, 1) * 2.6)
        container.sublayerTransform = perspective
        CATransaction.commit()
    }

    private func startScanning() {
        // Sway: a slow, continuous turn left and right with a slight nod.
        let yaw = CABasicAnimation(keyPath: "transform.rotation.y")
        yaw.fromValue = -0.16
        yaw.toValue = 0.16
        yaw.duration = 2.1
        yaw.autoreverses = true
        yaw.repeatCount = .infinity
        yaw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let nod = CABasicAnimation(keyPath: "transform.rotation.x")
        nod.fromValue = 0.05
        nod.toValue = -0.05
        nod.duration = 1.6
        nod.autoreverses = true
        nod.repeatCount = .infinity
        nod.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let group = CAAnimationGroup()
        group.animations = [yaw, nod]
        group.duration = .infinity
        imageLayer.add(group, forKey: "sway")
        beamHolder.add(group, forKey: "sway")

        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -bounds.width * 0.2
        sweep.toValue = bounds.width * 1.2
        sweep.duration = 2.0
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        beam.add(sweep, forKey: "sweep")
        beamHolder.isHidden = false

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 2.4
        spin.repeatCount = .infinity
        orbit.add(spin, forKey: "spin")
        fade(orbit, to: 1)
    }

    private func stopScanning() {
        // Settle back to rest from wherever the sway is.
        for target in [imageLayer, beamHolder] {
            let current = target.presentation()?.transform ?? CATransform3DIdentity
            target.removeAnimation(forKey: "sway")
            let settle = CABasicAnimation(keyPath: "transform")
            settle.fromValue = NSValue(caTransform3D: current)
            settle.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            settle.duration = 0.45
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            target.add(settle, forKey: "settle")
        }
        beam.removeAllAnimations()
        beamHolder.isHidden = true
        fade(orbit, to: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.scanning else { return }
            self.orbit.removeAnimation(forKey: "spin")
        }
    }

    private func fade(_ layer: CALayer, to opacity: Float) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        layer.opacity = opacity
        CATransaction.commit()
    }

    func celebrate() {
        // A swing across and back with a small pop.
        let swing = CAKeyframeAnimation(keyPath: "transform.rotation.y")
        swing.values = [0, 0.32, -0.22, 0.1, 0]
        swing.keyTimes = [0, 0.25, 0.55, 0.8, 1]
        swing.duration = 1.2
        swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageLayer.add(swing, forKey: "swing")
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [1, 1.08, 0.98, 1]
        pop.keyTimes = [0, 0.35, 0.7, 1]
        pop.duration = 0.7
        container.add(pop, forKey: "pop")
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
