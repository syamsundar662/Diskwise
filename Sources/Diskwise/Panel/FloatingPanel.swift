import AppKit

/// Borderless floating window for the panel, used instead of NSPopover: no
/// arrow, no system material, our own rounded shape and shadow. Drops in under
/// the menu bar item, also over full-screen apps, and closes on Esc or a click
/// anywhere else.
final class FloatingPanel: NSPanel {
    var onClose: (() -> Void)?
    private var anchor: NSRect = .zero
    private var outsideClicks: Any?

    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = content
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes the panel.
    override func cancelOperation(_ sender: Any?) { onClose?() }

    override func resignKey() {
        super.resignKey()
        onClose?()
    }

    /// Shows the panel under `anchor` (the menu bar item, in screen coordinates).
    func show(below anchor: NSRect, size: NSSize) {
        self.anchor = anchor
        let target = frame(for: size)
        setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
            animator().alphaValue = 1
        }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.onClose?()
        }
    }

    func hide() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    /// Follows the content's size, keeping the top edge under the menu bar.
    func resize(to size: NSSize) {
        guard isVisible, size.width > 0, size.height > 0 else { return }
        setFrame(frame(for: size), display: true)
        invalidateShadow()
    }

    private func frame(for size: NSSize) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let top = min(anchor.minY, visible.maxY) - 6
        return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }
}
