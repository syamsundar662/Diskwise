#!/usr/bin/env swift
// Draws the Diskwise app icon with AppKit/CoreGraphics and writes every macOS
// icon size into Resources/Assets.xcassets/AppIcon.appiconset, plus a
// Resources/AppIcon-1024.png copy for use in docs.
//
// Run with: swift scripts/make-icon.swift

import AppKit
import CoreGraphics
import Foundation

// MARK: - Colors

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

private func lerpColor(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> CGColor {
    let ar = CGFloat((a >> 16) & 0xFF) / 255, ag = CGFloat((a >> 8) & 0xFF) / 255, ab = CGFloat(a & 0xFF) / 255
    let br = CGFloat((b >> 16) & 0xFF) / 255, bg = CGFloat((b >> 8) & 0xFF) / 255, bb = CGFloat(b & 0xFF) / 255
    return CGColor(red: lerp(ar, br, t), green: lerp(ag, bg, t), blue: lerp(ab, bb, t), alpha: 1)
}

private let navyTop: UInt32 = 0x16295A
private let navyBottom: UInt32 = 0x050C22
private let cyan: UInt32 = 0x61DBF7
private let green: UInt32 = 0x73EE8F

// MARK: - Squircle (continuous corner) path

/// A full-bleed superellipse boundary, the Big Sur style "continuous corner"
/// rounded square, centered in a `size` x `size` canvas.
private func squirclePath(size: CGFloat, exponent n: CGFloat = 5, samplesPerQuadrant: Int = 72) -> CGPath {
    let a = size / 2
    let path = CGMutablePath()
    let totalSamples = samplesPerQuadrant * 4
    for i in 0...totalSamples {
        let t = CGFloat(i) / CGFloat(totalSamples) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = a * CGFloat(signOf(c)) * pow(abs(c), 2 / n)
        let y = a * CGFloat(signOf(s)) * pow(abs(s), 2 / n)
        let point = CGPoint(x: a + x, y: a + y)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

private func signOf(_ v: CGFloat) -> CGFloat { v < 0 ? -1 : (v > 0 ? 1 : 0) }

// MARK: - Drawing

private func drawIcon(in ctx: CGContext, size: CGFloat) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    ctx.saveGState()
    let squircle = squirclePath(size: size)
    ctx.addPath(squircle)
    ctx.clip()

    // Background gradient: deep navy, top-left to bottom-right.
    // CG's origin is bottom-left with a y-up axis, so "top-left" is (0, size)
    // and "bottom-right" is (size, 0).
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: [color(navyTop), color(navyBottom)] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    }

    // Soft blue radial glow behind the center.
    let glowCenter = CGPoint(x: size * 0.5, y: size * 0.52)
    if let glow = CGGradient(colorsSpace: colorSpace, colors: [color(0x3E7BFF, alpha: 0.38), color(0x3E7BFF, alpha: 0)] as CFArray, locations: [0, 1]) {
        ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: size * 0.40, options: [])
    }

    // Subtle vignette for depth at the bottom edge.
    if let vignette = CGGradient(colorsSpace: colorSpace, colors: [color(0x000000, alpha: 0.16), color(0x000000, alpha: 0)] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(vignette, start: CGPoint(x: size / 2, y: 0), end: CGPoint(x: size / 2, y: size * 0.38), options: [])
    }

    // Centered ring of short rounded tick marks, like a progress / usage ring.
    let tickCount = 56
    let filledCount = Int((CGFloat(tickCount) * 0.72).rounded())
    let ringRadius = size * 0.295
    let tickLength = size * 0.082
    let tickWidth = size * 0.0215
    let tickCorner = tickWidth / 2
    let center = CGPoint(x: size / 2, y: size / 2)

    for i in 0..<tickCount {
        // Start at 12 o'clock, proceed clockwise.
        let angle = CGFloat.pi / 2 - (2 * .pi * CGFloat(i) / CGFloat(tickCount))
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let tickCenter = CGPoint(x: center.x + dir.x * ringRadius, y: center.y + dir.y * ringRadius)

        ctx.saveGState()
        ctx.translateBy(x: tickCenter.x, y: tickCenter.y)
        ctx.rotate(by: angle)
        let rect = CGRect(x: -tickLength / 2, y: -tickWidth / 2, width: tickLength, height: tickWidth)
        let tickPath = CGPath(roundedRect: rect, cornerWidth: tickCorner, cornerHeight: tickCorner, transform: nil)

        if i < filledCount {
            let t = filledCount > 1 ? CGFloat(i) / CGFloat(filledCount - 1) : 0
            let fill = lerpColor(cyan, green, t)
            ctx.setShadow(offset: .zero, blur: tickWidth * 2.2, color: fill.copy(alpha: 0.85))
            ctx.addPath(tickPath)
            ctx.setFillColor(fill)
            ctx.fillPath()
        } else {
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.addPath(tickPath)
            ctx.setFillColor(color(0xFFFFFF, alpha: 0.18))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    // Subtle top highlight, like glass catching light.
    if let highlight = CGGradient(colorsSpace: colorSpace, colors: [color(0xFFFFFF, alpha: 0.13), color(0xFFFFFF, alpha: 0)] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(highlight, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: size * 0.48), options: [])
    }

    ctx.restoreGState()
}

// MARK: - Rendering

private func renderPNG(pixelSize: Int) -> Data {
    let size = CGFloat(pixelSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Could not create graphics context")
    }
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, size: size)
    guard let image = ctx.makeImage() else { fatalError("Could not make image") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
    return data
}

// MARK: - Iconset

struct IconSpec {
    let name: String   // base point size, e.g. "16x16"
    let scale: Int      // 1 or 2
    var pixels: Int { Int(name.split(separator: "x")[0])! * scale }
    var filename: String { scale == 1 ? "icon_\(name).png" : "icon_\(name)@2x.png" }
}

let specs: [IconSpec] = [
    IconSpec(name: "16x16", scale: 1),
    IconSpec(name: "16x16", scale: 2),
    IconSpec(name: "32x32", scale: 1),
    IconSpec(name: "32x32", scale: 2),
    IconSpec(name: "128x128", scale: 1),
    IconSpec(name: "128x128", scale: 2),
    IconSpec(name: "256x256", scale: 1),
    IconSpec(name: "256x256", scale: 2),
    IconSpec(name: "512x512", scale: 1),
    IconSpec(name: "512x512", scale: 2),
]

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repoRoot = scriptDir.deletingLastPathComponent()
let resourcesDir = repoRoot.appendingPathComponent("Resources")
let iconsetDir = resourcesDir.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")

try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

var images: [[String: String]] = []
for spec in specs {
    let data = renderPNG(pixelSize: spec.pixels)
    let url = iconsetDir.appendingPathComponent(spec.filename)
    try! data.write(to: url)
    images.append([
        "filename": spec.filename,
        "idiom": "mac",
        "scale": "\(spec.scale)x",
        "size": spec.name,
    ])
    print("Wrote \(url.path) (\(spec.pixels)x\(spec.pixels))")
}

let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1],
]
let contentsData = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! contentsData.write(to: iconsetDir.appendingPathComponent("Contents.json"))
print("Wrote \(iconsetDir.appendingPathComponent("Contents.json").path)")

// 1024 copy for docs (the 512@2x image is already 1024x1024).
let master = renderPNG(pixelSize: 1024)
let masterURL = resourcesDir.appendingPathComponent("AppIcon-1024.png")
try! master.write(to: masterURL)
print("Wrote \(masterURL.path)")
