import AppKit
import SwiftUI

// Diskwise: menu bar view of disk usage with cleanup, a folder explorer,
// large/old files, project junk and an app uninstaller.
//
// DISKWISE_SNAPSHOT=/tmp/sb renders every page off-screen to /tmp/sb-<page>.png
// and exits. Read-only: it never removes anything or saves state.

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if let base = ProcessInfo.processInfo.environment["DISKWISE_SNAPSHOT"] {
        Snapshot.run(base: base)
        app.run()
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

@MainActor
enum Snapshot {
    static func run(base: String) {
        let model = AppModel(readOnly: true)
        model.start()
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
            if ProcessInfo.processInfo.environment["DISKWISE_DESIGNS"] == "all" {
                var images: [(String, NSImage)] = []
                for (i, design) in WindowDesign.allCases.enumerated() {
                    let renderer = ImageRenderer(content: MainWindowMock(model: model, design: design))
                    renderer.scale = 2
                    if let image = renderer.nsImage {
                        images.append(("\(i + 1). \(design.rawValue)", image))
                        if let tiff = image.tiffRepresentation,
                           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(fileURLWithPath: "\(base)-design-\(i + 1).png"))
                        }
                    }
                }
                composite(images, columns: 2, "\(base)-designs.png")
                exit(0)
            }
            if ProcessInfo.processInfo.environment["DISKWISE_THEMES"] == "all" {
                compareThemes(model, "\(base)-themes.png")
                exit(0)
            }
            let pages: [(String, Page)] = [("home", .home), ("cleanup", .cleanup), ("explore", .explore([])),
                                           ("explore-library", .explore(["Library"])), ("files", .files),
                                           ("projects", .projects), ("apps", .apps)]
            for (name, page) in pages {
                model.page = page
                render(model, "\(base)-\(name).png")
            }
            if let app = model.apps.max(by: { ($0.size ?? 0) < ($1.size ?? 0) }) {
                model.openApp(app)
                var tries = 0
                while model.leftoversLoading, tries < 30 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    tries += 1
                }
                render(model, "\(base)-app.png")
            }
            model.page = .home
            model.confirmClean()
            render(model, "\(base)-confirm.png")
            model.confirmation = nil
            exit(0)
        }
    }

    /// The home page in every palette side by side, labelled, on a wallpaper-like backdrop.
    private static func compareThemes(_ model: AppModel, _ path: String) {
        let chosen = Theme.current
        let panels = Palette.all.compactMap { palette -> (String, NSImage)? in
            Theme.current = palette
            let renderer = ImageRenderer(content: PanelView(model: model, live: false))
            renderer.scale = 2
            return renderer.nsImage.map { (palette.name, $0) }
        }
        Theme.current = chosen
        let gap: CGFloat = 40, label: CGFloat = 34
        let size = NSSize(width: panels.reduce(gap) { $0 + $1.1.size.width + gap },
                          height: (panels.map(\.1.size.height).max() ?? 0) + gap * 2 + label)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(colors: [NSColor(red: 0.45, green: 0.52, blue: 0.68, alpha: 1), NSColor(red: 0.72, green: 0.62, blue: 0.66, alpha: 1),
                            NSColor(red: 0.36, green: 0.46, blue: 0.62, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: -20)
        var x = gap
        for (index, (name, panel)) in panels.enumerated() {
            let top = size.height - gap
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: NSColor.white]
            ("\(index + 1). \(name)" as NSString).draw(at: NSPoint(x: x + 4, y: top - 26), withAttributes: attributes)
            panel.draw(in: NSRect(x: x, y: top - label - panel.size.height, width: panel.size.width, height: panel.size.height))
            x += panel.size.width + gap
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Labelled images in a grid on a wallpaper-like backdrop.
    private static func composite(_ images: [(String, NSImage)], columns: Int, _ path: String) {
        guard let first = images.first?.1 else { return }
        let gap: CGFloat = 50, label: CGFloat = 40
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
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: NSColor.white]
            (name as NSString).draw(at: NSPoint(x: x + 4, y: top - 32), withAttributes: attributes)
            image.draw(in: NSRect(x: x, y: top - label - image.size.height, width: image.size.width, height: image.size.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func render(_ model: AppModel, _ path: String) {
        let renderer = ImageRenderer(content: PanelView(model: model, live: false))
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
