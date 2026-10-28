#!/usr/bin/env swift
// Renders the Juggler app icon with CoreGraphics and builds AppIcon.icns.
//
//   swift scripts/make-icon.swift [output-dir]     (default: Resources)
//
// Writes <output-dir>/AppIcon-1024.png and <output-dir>/AppIcon.icns.
// Needs only the Command Line Tools (CoreGraphics, ImageIO, /usr/bin/iconutil).
// Every iconset size is drawn directly at its pixel size (not downscaled),
// so the result is deterministic and crisp at 16 px.
//
// Geometry on the 1024 px canvas (all numbers in canvas units, y axis up):
//   background  824 x 824 rounded square, centred (100 px transparent margin), radius 185
//   balls       three equal circles, radius 100, in a triangle; their bounding
//               box is a 460 x 460 square centred on the background, so the margin
//               from the background edge is 182 px on all four sides
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let bgSide: CGFloat = 824
let bgRadius: CGFloat = 185
let ballRadius: CGFloat = 100
let groupSide: CGFloat = 460            // side of the balls' bounding box
let bgColor = (r: 0x1F, g: 0x2A, b: 0x44)
let balls: [(name: String, color: (r: Int, g: Int, b: Int), cx: CGFloat, cy: CGFloat)] = {
    let c = canvas / 2
    let d = groupSide / 2 - ballRadius              // horizontal offset of the bottom balls
    let bottom = c - groupSide / 2 + ballRadius     // y of the bottom centres
    let top = c + groupSide / 2 - ballRadius        // y of the top centre
    return [
        ("yellow", (0xF5, 0xB8, 0x3D), c, top),
        ("coral", (0xF2, 0x70, 0x5A), c - d, bottom),
        ("teal", (0x3C, 0xC2, 0xA8), c + d, bottom),
    ]
}()

func cgColor(_ c: (r: Int, g: Int, b: Int)) -> CGColor {
    CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
}

func render(pixels: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)

    let margin = (canvas - bgSide) / 2
    let bgRect = CGRect(x: margin, y: margin, width: bgSide, height: bgSide)
    ctx.setFillColor(cgColor(bgColor))
    ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: bgRadius, cornerHeight: bgRadius, transform: nil))
    ctx.fillPath()

    for ball in balls {
        ctx.setFillColor(cgColor(ball.color))
        ctx.fillEllipse(in: CGRect(x: ball.cx - ballRadius, y: ball.cy - ballRadius,
                                   width: ballRadius * 2, height: ballRadius * 2))
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot create \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "make-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
}

func run(_ tool: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw NSError(domain: "make-icon", code: Int(p.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(tool) failed with status \(p.terminationStatus)"])
    }
}

do {
    let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources",
                     isDirectory: true)
    let fm = FileManager.default
    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

    let work = fm.temporaryDirectory.appendingPathComponent("juggler-icon-\(ProcessInfo.processInfo.processIdentifier)")
    let iconset = work.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try? fm.removeItem(at: work)
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: work) }

    // (file name, pixel size) for every macOS iconset entry.
    let entries: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    var cache: [Int: CGImage] = [:]
    for (name, px) in entries {
        let image = cache[px] ?? render(pixels: px)
        cache[px] = image
        try writePNG(image, to: iconset.appendingPathComponent(name))
    }

    try writePNG(cache[1024]!, to: outDir.appendingPathComponent("AppIcon-1024.png"))
    try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path])

    print("Wrote \(outDir.path)/AppIcon-1024.png and \(outDir.path)/AppIcon.icns")
    for b in balls { print("  \(b.name): center (\(b.cx), \(b.cy)), radius \(ballRadius)") }
} catch {
    FileHandle.standardError.write(Data("make-icon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
