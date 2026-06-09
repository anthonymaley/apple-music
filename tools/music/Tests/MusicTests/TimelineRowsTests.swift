import XCTest
@testable import music

final class TimelineRowsTests: XCTestCase {
    // MARK: - trackKey

    func testTrackKeyIsDeterministicAndDistinguishes() {
        XCTAssertEqual(trackKey(title: "X", artist: "Y"), trackKey(title: "X", artist: "Y"))
        XCTAssertNotEqual(trackKey(title: "X", artist: "Y"), trackKey(title: "X", artist: "Z"))
        // A title-only collision must not match an artist-only one with swapped fields.
        XCTAssertNotEqual(trackKey(title: "AB", artist: ""), trackKey(title: "A", artist: "B"))
    }

    // Note: buildPlaylistRows / buildStandaloneRows were removed in 1.11.0 with the standalone
    // TUIs; splitTrackLine (their parser) was deleted as dead code in 1.11.2.
}
