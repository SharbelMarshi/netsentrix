#!/usr/bin/env swift
// Assembles dist/NetSentrix.app from the SPM release binary.
//
//   swift packaging/macos/app/bundle.swift [--with-engine]
//
// --with-engine also builds the Rust engine (release) and embeds it at
// Contents/Resources/bin/netsentrix-engine for installer use.
//
// The app icon is rasterized from docs/assets/logo-crystal-mark.svg via
// AppKit (native SVG decoding, macOS 11+), so no external tools are needed.

import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL
    .deletingLastPathComponent() // app
    .deletingLastPathComponent() // macos
    .deletingLastPathComponent() // packaging
    .deletingLastPathComponent() // repo root

let fm = FileManager.default
let withEngine = CommandLine.arguments.contains("--with-engine")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

@discardableResult
func run(_ launchPath: String, _ args: [String], cwd: URL? = nil) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    if let cwd { p.currentDirectoryURL = cwd }
    do {
        try p.run()
    } catch {
        fail("could not launch \(launchPath): \(error.localizedDescription)")
    }
    p.waitUntilExit()
    return p.terminationStatus
}

func step(_ name: String) {
    print("==> \(name)")
}

// 1. Build the app (release).
step("swift build -c release")
let appDir = repoRoot.appendingPathComponent("app")
guard run("/usr/bin/swift", ["build", "-c", "release"], cwd: appDir) == 0 else {
    fail("swift build failed")
}
let builtBinary = appDir.appendingPathComponent(".build/release/NetSentrix")
guard fm.fileExists(atPath: builtBinary.path) else {
    fail("expected binary at \(builtBinary.path)")
}

// 2. Optionally build + embed the engine.
var engineBinary: URL?
if withEngine {
    step("cargo build --release")
    let engineDir = repoRoot.appendingPathComponent("engine")
    guard run("/usr/bin/env", ["cargo", "build", "--release"], cwd: engineDir) == 0 else {
        fail("cargo build failed")
    }
    let bin = engineDir.appendingPathComponent("target/release/netsentrix-engine")
    guard fm.fileExists(atPath: bin.path) else {
        fail("expected engine binary at \(bin.path)")
    }
    engineBinary = bin
}

// 3. Rasterize the SVG logo into AppIcon.icns.
step("render AppIcon.icns from logo-crystal-mark.svg")
let svgURL = repoRoot.appendingPathComponent("docs/assets/logo-crystal-mark.svg")
guard let svgImage = NSImage(contentsOf: svgURL) else {
    fail("could not load \(svgURL.path)")
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fail("could not create bitmap rep (\(pixels)px)")
    }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fail("could not encode PNG (\(pixels)px)")
    }
    do {
        try png.write(to: url)
    } catch {
        fail("could not write \(url.path): \(error.localizedDescription)")
    }
}

let distDir = repoRoot.appendingPathComponent("dist")
let iconsetDir = distDir.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconsetDir)
try! fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// (filename base points, pixel size) pairs per iconutil conventions.
let iconSlots: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in iconSlots {
    writePNG(svgImage, pixels: pixels, to: iconsetDir.appendingPathComponent("\(name).png"))
}
let icnsURL = distDir.appendingPathComponent("AppIcon.icns")
guard run("/usr/bin/iconutil", ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]) == 0 else {
    fail("iconutil failed")
}
try? fm.removeItem(at: iconsetDir)

// 4. Assemble the bundle.
step("assemble dist/NetSentrix.app")
let bundleURL = distDir.appendingPathComponent("NetSentrix.app")
try? fm.removeItem(at: bundleURL)
let contents = bundleURL.appendingPathComponent("Contents")
let macOSDir = contents.appendingPathComponent("MacOS")
let resourcesDir = contents.appendingPathComponent("Resources")
try! fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)
try! fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

do {
    try fm.copyItem(at: builtBinary, to: macOSDir.appendingPathComponent("NetSentrix"))
    try fm.copyItem(
        at: scriptURL.deletingLastPathComponent().appendingPathComponent("Info.plist"),
        to: contents.appendingPathComponent("Info.plist")
    )
    try fm.moveItem(at: icnsURL, to: resourcesDir.appendingPathComponent("AppIcon.icns"))
    if let engineBinary {
        let binDir = resourcesDir.appendingPathComponent("bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fm.copyItem(at: engineBinary, to: binDir.appendingPathComponent("netsentrix-engine"))
    }
} catch {
    fail("bundle assembly failed: \(error.localizedDescription)")
}

// 5. Ad-hoc sign so the bundle runs locally without Gatekeeper complaints.
step("codesign (ad-hoc)")
guard run("/usr/bin/codesign", ["--force", "--deep", "-s", "-", bundleURL.path]) == 0 else {
    fail("codesign failed")
}

print("done: \(bundleURL.path)")
