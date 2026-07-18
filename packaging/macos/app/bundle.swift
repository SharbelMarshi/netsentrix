#!/usr/bin/env swift
// Builds dist/NetSentrix.app for distribution.
//
//   swift packaging/macos/app/bundle.swift [--app-only]
//
// Release-builds the Xcode project (app/NetSentrix.xcodeproj), then embeds the
// Rust engine at Contents/Resources/bin/netsentrix-engine plus the SMAppService
// daemon plist, and ad-hoc signs the result. --app-only skips the engine.
//
// The app icon is a committed asset (app/NetSentrix/AppIcon.icns), regenerated
// from docs/assets/logo-crystal-mark.svg only when the logo changes.

import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL
    .deletingLastPathComponent() // app
    .deletingLastPathComponent() // macos
    .deletingLastPathComponent() // packaging
    .deletingLastPathComponent() // repo root

let fm = FileManager.default
let withEngine = !CommandLine.arguments.contains("--app-only")

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

let distDir = repoRoot.appendingPathComponent("dist")
let derivedData = distDir.appendingPathComponent("DerivedData")
let appDir = repoRoot.appendingPathComponent("app")

// 1. Release-build the app via Xcode.
step("xcodebuild -configuration Release")
guard run("/usr/bin/xcodebuild", [
    "-project", appDir.appendingPathComponent("NetSentrix.xcodeproj").path,
    "-scheme", "NetSentrix",
    "-configuration", "Release",
    "-destination", "platform=macOS",
    "-derivedDataPath", derivedData.path,
    "build",
    "-quiet",
]) == 0 else {
    fail("xcodebuild failed")
}
let builtApp = derivedData.appendingPathComponent("Build/Products/Release/NetSentrix.app")
guard fm.fileExists(atPath: builtApp.path) else {
    fail("expected app at \(builtApp.path)")
}

// 2. Optionally build the engine.
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

// 3. Stage into dist/ and embed the engine.
step("assemble dist/NetSentrix.app")
let bundleURL = distDir.appendingPathComponent("NetSentrix.app")
try? fm.removeItem(at: bundleURL)
do {
    try fm.createDirectory(at: distDir, withIntermediateDirectories: true)
    try fm.copyItem(at: builtApp, to: bundleURL)
    if let engineBinary {
        let contents = bundleURL.appendingPathComponent("Contents")
        let binDir = contents.appendingPathComponent("Resources/bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        try fm.copyItem(at: engineBinary, to: binDir.appendingPathComponent("netsentrix-engine"))
        let daemonsDir = contents.appendingPathComponent("Library/LaunchDaemons")
        try fm.createDirectory(at: daemonsDir, withIntermediateDirectories: true)
        try fm.copyItem(
            at: scriptURL.deletingLastPathComponent().appendingPathComponent("com.netsentrix.engine.plist"),
            to: daemonsDir.appendingPathComponent("com.netsentrix.engine.plist")
        )
    }
} catch {
    fail("bundle assembly failed: \(error.localizedDescription)")
}

// 4. Re-sign (embedding invalidated the build signature).
step("codesign (ad-hoc)")
guard run("/usr/bin/codesign", ["--force", "--deep", "-s", "-", bundleURL.path]) == 0 else {
    fail("codesign failed")
}

print("done: \(bundleURL.path)")
