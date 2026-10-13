import AppKit
import Combine
import SwiftUI
import DiskwiseCore

/// Owns the menu bar item (drive icon + percent used) and the floating panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model = AppModel()
    private var panel: FloatingPanel!
    private var host: NSHostingView<PanelView>!
    private var panelOpen = false
    private var panelSize = NSSize(width: PanelView.width, height: 600)
    private var changes: AnyCancellable?
    private var closedAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = Self.driveIcon(color: nil)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
        }
        host = NSHostingView(rootView: PanelView(model: model, onSize: { [weak self] size in
            // Resize after SwiftUI's layout pass, not during it.
            DispatchQueue.main.async {
                self?.panelSize = size
                self?.panel?.resize(to: size)
            }
        }))
        panel = FloatingPanel(content: host)
        panel.onClose = { [weak self] in self?.closePanel() }

        changes = model.$disk.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateButton() }
        }
        model.start()
        updateButton()
    }

    @objc private func togglePanel() {
        if panelOpen {
            closePanel()
        } else if Date().timeIntervalSince(closedAt) > 0.3 {
            // A click on the item may first close the panel through its
            // outside-click handling; don't let the same click reopen it.
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        panelOpen = true
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let fitting = host.fittingSize
        panel.show(below: anchor, size: fitting.height > 0 ? fitting : panelSize)
        model.refreshIfStale()
    }

    private func closePanel() {
        guard panelOpen else { return }
        // Keep the panel open while asking for confirmation or working.
        panelOpen = false
        closedAt = Date()
        model.confirmation = nil
        panel.hide()
    }

    /// Template (follows the menu bar) when fine, colored when space is low.
    private static func driveIcon(color: NSColor?) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let color { config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color])) }
        let image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "Storage")?.withSymbolConfiguration(config)
        image?.isTemplate = color == nil
        return image
    }

    /// "97%" next to the drive icon; orange under 20 GB free, red under 10 GB.
    private func updateButton() {
        guard let button = statusItem.button else { return }
        guard let disk = model.disk else {
            button.title = ""
            return
        }
        // The menu bar ignores contentTintColor, so warning states use colored text and icon.
        let color: NSColor?
        switch SpaceLevel(available: disk.available) {
        case .fine: color = nil
        case .low: color = .systemOrange
        case .critical: color = .systemRed
        }
        button.image = Self.driveIcon(color: color)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        let text = " \(disk.usedPercent)%"
        if let color {
            button.attributedTitle = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        } else {
            button.font = font
            button.title = text
        }
        let tip = "\(Bytes.format(disk.available)) available of \(Bytes.format(disk.total))"
        button.toolTip = tip
        button.setAccessibilityLabel("Storage: \(disk.usedPercent)% used, \(tip)")
    }
}
