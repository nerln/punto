#!/usr/bin/swift
import AppKit
import Foundation

// Native vector artwork, rasterized at every standard macOS icon size.
guard CommandLine.arguments.count == 2 else {
    fputs("Uso: swift make-icon.swift /percorso/Punto.iconset\n", stderr)
    exit(1)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func drawIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "Punto.Icon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    let factor = CGFloat(pixels) / 1024
    context.scaleBy(x: factor, y: factor)
    context.setAllowsAntialiasing(true)

    let rect = NSRect(x: 102, y: 102, width: 820, height: 820)
    let body = NSBezierPath(roundedRect: rect, xRadius: 182, yRadius: 182)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 35
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.72, green: 0.92, blue: 0.56, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.82, green: 0.98, blue: 0.68, alpha: 1),
                              ending: NSColor(calibratedRed: 0.64, green: 0.86, blue: 0.48, alpha: 1))!
    gradient.draw(in: body, angle: -75)
    NSColor.white.withAlphaComponent(0.3).setStroke()
    body.lineWidth = 2
    body.stroke()

    let ink = NSColor(calibratedRed: 0.065, green: 0.105, blue: 0.085, alpha: 1)
    ink.setStroke()
    for (x, y, dx, dy) in [
        (CGFloat(302), CGFloat(302), CGFloat(1), CGFloat(1)),
        (CGFloat(722), CGFloat(302), CGFloat(-1), CGFloat(1)),
        (CGFloat(302), CGFloat(722), CGFloat(1), CGFloat(-1)),
        (CGFloat(722), CGFloat(722), CGFloat(-1), CGFloat(-1))
    ] {
        let corner = NSBezierPath()
        corner.move(to: NSPoint(x: x, y: y + dy * 110))
        corner.line(to: NSPoint(x: x, y: y))
        corner.line(to: NSPoint(x: x + dx * 110, y: y))
        corner.lineWidth = 45
        corner.lineCapStyle = .round
        corner.lineJoinStyle = .round
        corner.stroke()
    }
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: 450, y: 450, width: 124, height: 124), xRadius: 14, yRadius: 14).fill()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Punto.Icon", code: 2)
    }
    return data
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let destination = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try drawIcon(pixels: size * scale).write(to: destination)
    }
}
print("Icona generata: \(directory.path)")
