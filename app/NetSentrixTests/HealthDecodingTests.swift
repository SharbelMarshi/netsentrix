import XCTest
@testable import NetSentrix

final class HealthDecodingTests: XCTestCase {
    func testDecodesMinimalHealthFixture() throws {
        let bundle = Bundle(for: HealthDecodingTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "health_minimal", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "health_minimal", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)

        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.engine, "netsentrix-engine")
        XCTAssertEqual(health.apiListen, "127.0.0.1:8756")
        XCTAssertEqual(health.dnsListen, "127.0.0.1:5353")
        XCTAssertTrue(health.dnsBound)
        XCTAssertEqual(health.dnsUdpBound, true)
        XCTAssertEqual(health.dnsTcpBound, true)
        XCTAssertNil(health.dnsLastError)
        XCTAssertEqual(health.engineStatus, "running")
        XCTAssertEqual(health.dnsPaused, false)
        XCTAssertNil(health.protection)
        XCTAssertEqual(health.setupHints?.isEmpty, true)
    }

    /// Older engines omit optional keys entirely — decoding must not fail.
    func testDecodesLegacyPayloadWithoutOptionalKeys() throws {
        let legacy = """
        {
          "ok": true,
          "version": "0.0.1",
          "engine": "netsentrix-engine",
          "api_listen": "127.0.0.1:8756",
          "dns_listen": "127.0.0.1:5353",
          "dns_bound": true,
          "dns_last_error": null,
          "dns_tcp_last_error": null,
          "engine_status": "running",
          "suggested_lan_ip": null
        }
        """
        let health = try JSONDecoder().decode(HealthResponse.self, from: Data(legacy.utf8))
        XCTAssertNil(health.dnsUdpBound)
        XCTAssertNil(health.dnsTcpBound)
        XCTAssertNil(health.protection)
        XCTAssertNil(health.setupHints)
    }
}
