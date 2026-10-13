import AppKit
import Combine
import SwiftUI
import DiskwiseCore

/// Owns the menu bar item and its panel, the main window, the Settings window
/// and the main menu. The app shows in the Dock only while a window is open.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private let prefs = Preferences.shared
    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel!
    private var host: NSHostingView<PanelView>!
    private var panelOpen = false
    private var panelSize = NSSize(width: PanelView.width, height: 600)
    private var closedAt = Date.distantPast
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var changes: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let atLogin = Self.launchedAtLogin()
        NSApp.mainMenu = MainMenu.build()
        host = NSHostingView(rootView: PanelView(model: model, onSize: { [weak self] size in
            // Resize after SwiftUI's layout pass, not during it.
            DispatchQueue.main.async {
                self?.panelSize = size
                self?.panel?.resize(to: size)
            }
        }))
        panel = FloatingPanel(content: host)
        panel.onClose = { [weak self] in self?.closePanel() }

        model.$disk.sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusItem() } }.store(in: &changes)
        NotificationCenter.default.publisher(for: .menuBarItemSettingChanged)
            .sink { [weak self] _ in self?.updateStatusItem() }.store(in: &changes)

        model.start()
        _ = Updater.shared  // starts Sparkle's scheduled update checks
        updateStatusItem()
        if !atLogin || !prefs.onboardingDone || !prefs.showMenuBarItem {
            showMainWindow(nil)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Windows

    @objc func showMainWindow(_ sender: Any?) {
        closePanel()
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "Diskwise"
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(red: 0.04, green: 0.08, blue: 0.19, alpha: 1)
            window.minSize = MainView.minSize
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: MainView(model: model))
            window.setFrameAutosaveName("DiskwiseMainWindow")
            if !window.setFrameUsingName("DiskwiseMainWindow") { window.center() }
            mainWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.refreshIfStale()
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsView.size),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "Diskwise Settings"
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        closePanel()
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu bar app once no window is left, unless there's no menu bar item to come back to.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let open = [self.mainWindow, self.settingsWindow].contains { $0?.isVisible == true }
            if !open, self.prefs.showMenuBarItem { NSApp.setActivationPolicy(.accessory) }
        }
    }

    // MARK: Menu actions

    @objc func rescan(_ sender: Any?) { model.refreshAll() }

    @objc func showSection(_ sender: NSMenuItem) {
        guard NavItem.allCases.indices.contains(sender.tag) else { return }
        showMainWindow(nil)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { model.section = NavItem.allCases[sender.tag] }
    }

    @objc func checkForUpdates(_ sender: Any?) { Updater.shared.checkForUpdates() }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Diskwise",
            .credits: NSAttributedString(string: "See what fills your Mac and free up space, safely.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    // MARK: Menu bar item

    private func updateStatusItem() {
        guard prefs.showMenuBarItem else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            closePanel()
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.imagePosition = .imageLeading
            item.button?.target = self
            item.button?.action = #selector(togglePanel)
            statusItem = item
        }
        guard let button = statusItem?.button else { return }
        guard let disk = model.disk else {
            button.image = Self.driveIcon(color: nil)
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
        button.setAccessibilityLabel("Diskwise: \(disk.usedPercent)% used, \(tip)")
    }

    /// Template (follows the menu bar) when fine, colored when space is low.
    private static func driveIcon(color: NSColor?) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let color { config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color])) }
        let image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "Diskwise")?.withSymbolConfiguration(config)
        image?.isTemplate = color == nil
        return image
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
        guard let button = statusItem?.button, let window = button.window else { return }
        panelOpen = true
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let fitting = host.fittingSize
        panel.show(below: anchor, size: fitting.height > 0 ? fitting : panelSize)
        model.refreshIfStale()
    }

    private func closePanel() {
        guard panelOpen else { return }
        panelOpen = false
        closedAt = Date()
        if mainWindow?.isVisible != true { model.confirmation = nil }
        panel.hide()
    }

    /// True when macOS opened the app as a login item.
    private static func launchedAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

/// The menu bar menus with their keyboard shortcuts.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "Diskwise")
        app.addItem(item("About Diskwise", #selector(AppDelegate.showAbout(_:))))
        app.addItem(item("Check for Updates...", #selector(AppDelegate.checkForUpdates(_:))))
        app.addItem(.separator())
        app.addItem(item("Settings...", #selector(AppDelegate.showSettings(_:)), ","))
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        app.addItem(services)
        app.addItem(.separator())
        app.addItem(item("Hide Diskwise", #selector(NSApplication.hide(_:)), "h"))
        let others = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(others)
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit Diskwise", #selector(NSApplication.terminate(_:)), "q"))
        main.addItem(submenu(app))

        let file = NSMenu(title: "File")
        file.addItem(item("Open Diskwise", #selector(AppDelegate.showMainWindow(_:)), "n"))
        file.addItem(item("Rescan", #selector(AppDelegate.rescan(_:)), "r"))
        file.addItem(.separator())
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        main.addItem(submenu(file))

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        main.addItem(submenu(edit))

        let view = NSMenu(title: "View")
        for (i, section) in NavItem.allCases.enumerated() {
            let entry = item(section.rawValue, #selector(AppDelegate.showSection(_:)), String(section.shortcut))
            entry.tag = i
            view.addItem(entry)
        }
        main.addItem(submenu(view))

        let window = NSMenu(title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = window
        main.addItem(submenu(window))
        return main
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
