#!/usr/bin/env swift
// Draws an optional background image for the release DMG: a simple navy
// panel (matching the app icon's palette) with an arrow hint from the app
// icon position towards the Applications symlink. Not required: release.sh
// falls back to a DMG with no custom background if this is skipped or fails.
//
// Run with: swift scripts/make-dmg-background.swift <output.png>

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write("Usage: make-dmg-background.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outputPath = args[1]

// Standard Finder DMG window size used by release.sh.
let width = 660
let height = 400
let scale = 2 // render at 2x for a crisp Retina background

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

let pixelWidth = width * scale
let pixelHeight = height * scale
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Could not create graphics context")
}
ctx.interpolationQuality = .high

let size = CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))

// Background gradient, same deep navy as the app icon.
if let gradient = CGGradient(colorsSpace: colorSpace, colors: [color(0x16295A), color(0x050C22)] as CFArray, locations: [0, 1]) {
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
}

// A soft divider line and arrow between where Finder will place the app
// icon (left third) and the Applications symlink (right third).
let midY = size.height * 0.46
let fromX = size.width * 0.33
let toX = size.width * 0.64

ctx.saveGState()
ctx.setStrokeColor(color(0x61DBF7, alpha: 0.55))
ctx.setLineWidth(CGFloat(scale) * 2)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: fromX, y: midY))
ctx.addLine(to: CGPoint(x: toX, y: midY))
ctx.strokePath()

// Arrowhead.
let headSize = CGFloat(scale) * 10
ctx.move(to: CGPoint(x: toX, y: midY))
ctx.addLine(to: CGPoint(x: toX - headSize, y: midY + headSize * 0.6))
ctx.addLine(to: CGPoint(x: toX - headSize, y: midY - headSize * 0.6))
ctx.closePath()
ctx.setFillColor(color(0x61DBF7, alpha: 0.55))
ctx.fillPath()
ctx.restoreGState()

// "Drag Diskwise to Applications" label near the bottom.
let text = "Drag Diskwise to Applications to install"
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: CGFloat(13 * scale), weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.72),
]
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let attributed = NSAttributedString(string: text, attributes: attributes)
let textSize = attributed.size()
attributed.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: size.height * 0.14))
NSGraphicsContext.restoreGraphicsState()

guard let image = ctx.makeImage() else { fatalError("Could not make image") }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: width, height: height)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
try! data.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath) (\(pixelWidth)x\(pixelHeight))")
