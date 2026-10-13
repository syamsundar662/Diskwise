import AppKit
import SwiftUI

// Diskwise: see what fills your Mac and free up space safely. A main window
// plus a menu bar item with a quick panel.
//
// DISKWISE_SNAPSHOT=/tmp/dw renders every window page, the onboarding steps,
// Settings and the menu bar panel off-screen to /tmp/dw-<name>.png and exits.
// Read-only: it never removes anything.

MainActor.assumeIsolated {
    let app = NSApplication.shared
    if let base = ProcessInfo.processInfo.environment["DISKWISE_SNAPSHOT"] {
        app.setActivationPolicy(.accessory)
        Snapshot.run(base: base)
        app.run()
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

@MainActor
enum Snapshot {
    static let windowSize = CGSize(width: 1120, height: 740)

    static func run(base: String) {
        RenderMode.snapshot = true
        let model = AppModel(readOnly: true)
        model.start()
        if model.scan == nil { model.startScan() }
        Task { @MainActor in
            @MainActor func ready() -> Bool {
                !model.cleanupLoading && model.cleanupDate != nil && model.scan != nil
                    && !model.apps.isEmpty && !model.apps.contains { $0.size == nil }
            }
            var waited = 0
            while waited < 400, !ready() {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                waited += 1
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if ProcessInfo.processInfo.environment["DISKWISE_CARE"] == "all" {
                var images: [(String, NSImage)] = []
                for design in CareDesign.allCases {
                    let renderer = ImageRenderer(content: CareWindowMock(model: model, design: design))
                    renderer.scale = 2
                    guard let image = renderer.nsImage else { continue }
                    images.append(("\(design.rawValue + 1). \(design.title)", image))
                    if let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: "\(base)-care-\(design.rawValue + 1).png"))
                    }
                }
                composite(images, columns: 2, "\(base)-care-all.png")
                exit(0)
            }
            let prefs = Preferences.shared
            let onboarded = prefs.onboardingDone
            prefs.onboardingDone = true

            for section in NavItem.allCases {
                model.section = section
                render(window(model), "\(base)-window-\(name(section)).png")
            }
            if let app = model.apps.max(by: { ($0.size ?? 0) < ($1.size ?? 0) }) {
                model.section = .apps
                model.loadLeftovers(for: app)
                model.windowApp = app.path
                var tries = 0
                while model.leftoversLoading, tries < 30 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    tries += 1
                }
                render(window(model), "\(base)-window-app.png")
                model.windowApp = nil
            }
            model.section = .dashboard
            model.cleaning = CleaningState(total: 41_300_000_000, freed: 17_800_000_000, current: "npm cache: _cacache")
            render(window(model), "\(base)-window-cleaning.png")
            model.cleaning = CleaningState(total: 41_300_000_000, freed: 41_300_000_000, finished: true)
            render(window(model), "\(base)-window-cleaned.png")
            model.cleaning = nil
            model.confirmClean()
            render(window(model), "\(base)-window-confirm.png")
            model.confirmation = nil

            for step in 0..<3 {
                render(OnboardingView(model: model, live: false, step: step).frame(width: windowSize.width, height: windowSize.height),
                       "\(base)-onboarding-\(step + 1).png")
            }
            for tab in SettingsView.Tab.allCases {
                render(SettingsView(model: model, tab: tab), "\(base)-settings-\(tab.rawValue.lowercased()).png")
            }
            model.page = .home
            render(PanelView(model: model, live: false), "\(base)-panel.png")
            prefs.onboardingDone = onboarded
            exit(0)
        }
    }

    /// Labelled images in a grid on a wallpaper-like backdrop, at half their pixel size.
    private static func composite(_ images: [(String, NSImage)], columns: Int, _ path: String) {
        guard let first = images.first?.1 else { return }
        let gap: CGFloat = 50, label: CGFloat = 44
        let cell = NSSize(width: first.size.width, height: first.size.height + label)
        let rows = (images.count + columns - 1) / columns
        let size = NSSize(width: CGFloat(columns) * (cell.width + gap) + gap, height: CGFloat(rows) * (cell.height + gap) + gap)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(colors: [NSColor(red: 0.45, green: 0.52, blue: 0.68, alpha: 1), NSColor(red: 0.72, green: 0.62, blue: 0.66, alpha: 1),
                            NSColor(red: 0.36, green: 0.46, blue: 0.62, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: -20)
        for (i, (name, image)) in images.enumerated() {
            let x = gap + CGFloat(i % columns) * (cell.width + gap)
            let top = size.height - gap - CGFloat(i / columns) * (cell.height + gap)
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white]
            (name as NSString).draw(at: NSPoint(x: x + 4, y: top - 36), withAttributes: attributes)
            image.draw(in: NSRect(x: x, y: top - label - image.size.height, width: image.size.width, height: image.size.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func window(_ model: AppModel) -> some View {
        MainView(model: model, live: false)
            .frame(width: windowSize.width, height: windowSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static func name(_ section: NavItem) -> String {
        section.rawValue.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-")
    }

    private static func render<V: View>(_ view: V, _ path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
