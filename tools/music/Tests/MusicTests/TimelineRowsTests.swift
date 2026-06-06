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

    // MARK: - buildPlaylistRows (history overlay)

    func testPlaylistRowsMarkCurrentAndPlayed() {
        let tracks = ["Song1 \u{2014} Art1", "Song2 \u{2014} Art2", "Song3 \u{2014} Art3"]
        let history = [(track: "Song1", artist: "Art1")]
        let rows = buildPlaylistRows(contextTracks: tracks, history: history, currentIndex: 1)

        XCTAssertEqual(rows.count, 3)
        // 1-based playlist index preserved.
        XCTAssertEqual(rows.map { $0.index }, [1, 2, 3])
        // currentIndex 1 -> second row is current.
        XCTAssertEqual(rows.map { $0.isCurrent }, [false, true, false])
        // Only Song1 is in history -> wasPlayed overlay.
        XCTAssertEqual(rows.map { $0.wasPlayed }, [true, false, false])
    }

    func testPlaylistRowsNoCurrentWhenIndexNil() {
        let rows = buildPlaylistRows(contextTracks: ["A \u{2014} B"], history: [], currentIndex: nil)
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].isCurrent)
        XCTAssertFalse(rows[0].wasPlayed)
    }

    // MARK: - buildStandaloneRows (dedup history against the live surrounding list)

    func testStandaloneRowsDedupHistoryAgainstSurrounding() {
        // History contains A and B; B is also in the surrounding (live) list.
        // The B history row must be suppressed (no duplicate), A kept as history.
        let history = [(track: "A", artist: "ArtA"), (track: "B", artist: "ArtB")]
        let surrounding = [
            TrackListEntry(index: 5, name: "B", artist: "ArtB", isCurrent: true),
            TrackListEntry(index: 6, name: "C", artist: "ArtC", isCurrent: false),
        ]
        let rows = buildStandaloneRows(history: history, surrounding: surrounding)

        // Expected order: history (deduped, reversed) then surrounding.
        // history.reversed() = [B, A]; B dropped (in surrounding) -> [A]; then B, C.
        XCTAssertEqual(rows.map { $0.title }, ["A", "B", "C"])
        XCTAssertEqual(rows.map { $0.kind }, [.history, .queue, .queue])
        // B is current and was played; C neither; A is a played history row.
        XCTAssertEqual(rows.map { $0.isCurrent }, [false, true, false])
        XCTAssertEqual(rows.map { $0.wasPlayed }, [true, true, false])
    }

    func testStandaloneRowsEmptyHistory() {
        let surrounding = [TrackListEntry(index: 1, name: "Only", artist: "Artist", isCurrent: true)]
        let rows = buildStandaloneRows(history: [], surrounding: surrounding)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "Only")
        XCTAssertTrue(rows[0].isCurrent)
        XCTAssertFalse(rows[0].wasPlayed)
    }
}
