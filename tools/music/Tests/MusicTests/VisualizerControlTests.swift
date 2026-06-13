import XCTest
@testable import music

final class VisualizerControlTests: XCTestCase {
    func testMarkOn() {
        XCTAssertTrue(parseVisualizerMark("\u{2713}"))   // ✓
        XCTAssertTrue(parseVisualizerMark(" \u{2713} ")) // trimmed
    }

    func testMarkOff() {
        XCTAssertFalse(parseVisualizerMark("missing value"))
        XCTAssertFalse(parseVisualizerMark(""))
    }
}
