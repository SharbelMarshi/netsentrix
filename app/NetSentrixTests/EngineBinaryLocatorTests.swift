import XCTest
@testable import NetSentrix

final class EngineBinaryLocatorTests: XCTestCase {
    func testEnvOverrideWinsWhenExecutable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netsentrix-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fake = dir.appendingPathComponent("netsentrix-engine")
        FileManager.default.createFile(
            atPath: fake.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )

        let found = EngineProcessManager.locateEngineBinary(env: ["NETSENTRIX_ENGINE_BIN": fake.path])
        XCTAssertEqual(found?.standardizedFileURL.path, fake.standardizedFileURL.path)
    }

    func testNonExecutableOverrideIsSkipped() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("netsentrix-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let plain = dir.appendingPathComponent("not-executable")
        FileManager.default.createFile(atPath: plain.path, contents: Data(), attributes: [.posixPermissions: 0o644])

        let found = EngineProcessManager.locateEngineBinary(env: ["NETSENTRIX_ENGINE_BIN": plain.path])
        XCTAssertNotEqual(found?.standardizedFileURL.path, plain.standardizedFileURL.path)
    }
}
