import XCTest
@testable import music

final class TimelineRowsTests: XCTestCase {
    // MARK: - splitTrackLine

    func testSplitsTitleAndArtistOnEmDash() {
        let r = splitTrackLine("Bohemian Rhapsody \u{2014} Queen")
        XCTAssertEqual(r.title, "Bohemian Rhapsody")
        XCTAssertEqual(r.artist, "Queen")
    }

    func testNoEmDashKeepsWholeLineAsTitle() {
        let r = splitTrackLine("Some Track With No Artist")
        XCTAssertEqual(r.title, "Some Track With No Artist")
        XCTAssertEqual(r.artist, "")
    }

    func testSplitsOnlyOnFirstEmDash() {
        // A title or artist may itself contain an em-dash; only the first splits.
        let r = splitTrackLine("A \u{2014} B \u{2014} C")
        XCTAssertEqual(r.title, "A")
        XCTAssertEqual(r.artist, "B \u{2014} C")
    }

    // MARK: - trackKey

    func testTrackKeyIsDeterministicAndDistinguishes() {
        XCTAssertEqual(trackKey(title: "X", artist: "Y"), trackKey(title: "X", artist: "Y"))
        XCTAssertNotEqual(trackKey(title: "X", artist: "Y"), trackKey(title: "X", artist: "Z"))
        // A title-only collision must not match an artist-only one with swapped fields.
        XCTAssertNotEqual(trackKey(title: "AB", artist: ""), trackKey(title: "A", artist: "B"))
    }

    // Note: buildPlaylistRows / buildStandaloneRows were removed in 1.11.0 along with the
    // standalone music now/playlist TUIs; their tests were deleted with them. splitTrackLine
    // and trackKey survive in NowPlayingTUI.swift (the music now CLI subcommand still parses tracks).
}
