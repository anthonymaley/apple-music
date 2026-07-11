// tools/music/Tests/MusicTests/RouteHealerTests.swift
import XCTest
@testable import music

final class RouteHealerTests: XCTestCase {
    func testTier3MessageNamesManualFixAndEvidence() {
        let msg = RouteHealer.honestFailureMessage(
            speaker: "Kitchen", ip: "192.168.1.112",
            evidence: "no new connections to 192.168.1.112 within 5s",
            scriptingClaims: "selected=true active=false")
        XCTAssertTrue(msg.contains("NOT verified"))
        XCTAssertTrue(msg.contains("click the AirPlay icon in Music"))
        XCTAssertTrue(msg.contains("deselect and reselect Kitchen"))
        XCTAssertTrue(msg.contains("192.168.1.112"))
        XCTAssertTrue(msg.contains("selected=true active=false"))
    }

    func testOutcomeReportsTierUsed() {
        let healed = RouteHealer.Outcome(healed: true, tierUsed: 1, failure: nil)
        XCTAssertEqual(healed.tierUsed, 1)
        XCTAssertNil(healed.failure)
    }
}
