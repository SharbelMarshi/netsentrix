import XCTest
@testable import NetSentrix

final class DomainPatternTests: XCTestCase {
    func testTrimsAndLowercases() {
        XCTAssertEqual(DomainPattern.normalize("  Ads.Example.COM  "), "ads.example.com")
    }

    func testStripsTrailingDots() {
        XCTAssertEqual(DomainPattern.normalize("tracker.example.com."), "tracker.example.com")
        XCTAssertEqual(DomainPattern.normalize("tracker.example.com..."), "tracker.example.com")
    }

    func testEmptyAndWhitespaceInputs() {
        XCTAssertEqual(DomainPattern.normalize(""), "")
        XCTAssertEqual(DomainPattern.normalize("   "), "")
        XCTAssertEqual(DomainPattern.normalize("."), "")
    }
}
