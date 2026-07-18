import XCTest
@testable import NetSentrix

final class EngineEndpointTests: XCTestCase {
    func testBareHostPortGetsHTTPScheme() {
        XCTAssertEqual(EngineEndpoint.normalize("127.0.0.1:8756")?.absoluteString, "http://127.0.0.1:8756")
    }

    func testExplicitSchemeKept() {
        XCTAssertEqual(EngineEndpoint.normalize("https://box.local:8756")?.absoluteString, "https://box.local:8756")
    }

    func testTrailingSlashesStripped() {
        XCTAssertEqual(EngineEndpoint.normalize("http://127.0.0.1:8756///")?.absoluteString, "http://127.0.0.1:8756")
    }

    func testRejectsEmptyAndGarbage() {
        XCTAssertNil(EngineEndpoint.normalize(""))
        XCTAssertNil(EngineEndpoint.normalize("   "))
        XCTAssertNil(EngineEndpoint.normalize("ftp://127.0.0.1:21"))
    }
}
