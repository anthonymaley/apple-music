// tools/music/Tests/MusicTests/QueueEndTests.swift
import XCTest
@testable import music

final class QueueEndTests: XCTestCase {
    func testLibraryNameDetection() {
        XCTAssertTrue(isLibraryContextName("Music"))
        XCTAssertTrue(isLibraryContextName("Library"))
        XCTAssertFalse(isLibraryContextName("Friday Mix"))
        XCTAssertFalse(isLibraryContextName(""))
    }
    func testFiresOnNaturalQueueEnd() {
        XCTAssertTrue(detectQueueEnd(
            prevWasRealPlaylist: true, prevAtLastTrack: true,
            prevNaturalEnd: true, nowIsLibraryAutoplay: true))
    }
    func testNoFireWhenPrevWasLibrary() {
        XCTAssertFalse(detectQueueEnd(
            prevWasRealPlaylist: false, prevAtLastTrack: true,
            prevNaturalEnd: true, nowIsLibraryAutoplay: true))
    }
    func testNoFireMidPlaylist() {
        XCTAssertFalse(detectQueueEnd(
            prevWasRealPlaylist: true, prevAtLastTrack: false,
            prevNaturalEnd: true, nowIsLibraryAutoplay: true))
    }
    func testNoFireOnManualLibraryJump() {
        // prev was last track but not a natural end (user skipped to library)
        XCTAssertFalse(detectQueueEnd(
            prevWasRealPlaylist: true, prevAtLastTrack: true,
            prevNaturalEnd: false, nowIsLibraryAutoplay: true))
    }
    func testNoFireWhenStillInPlaylist() {
        XCTAssertFalse(detectQueueEnd(
            prevWasRealPlaylist: true, prevAtLastTrack: true,
            prevNaturalEnd: true, nowIsLibraryAutoplay: false))
    }
    // MARK: - Cursor snap (the wrong-track-on-Enter bug)

    func testSnapFindsCurrentRowMatchingNewTrack() {
        let rows = [
            TrackListEntry(index: 1, name: "A", artist: "X", isCurrent: false),
            TrackListEntry(index: 2, name: "B", artist: "Y", isCurrent: true),
        ]
        XCTAssertEqual(snapCursorIndex(rows: rows, currentKey: trackKey(title: "B", artist: "Y")), 1)
    }

    func testSnapRefusesStaleWindowWhereCurrentIsTheOldTrack() {
        // The poller's fast-publish still carries the previous context: a row is
        // marked current, but it is NOT the new track. Snapping here parked the
        // cursor on a stale position for good.
        let rows = [
            TrackListEntry(index: 1, name: "Old Song", artist: "Old Artist", isCurrent: true),
            TrackListEntry(index: 2, name: "B", artist: "Y", isCurrent: false),
        ]
        XCTAssertNil(snapCursorIndex(rows: rows, currentKey: trackKey(title: "New Song", artist: "New Artist")))
    }

    func testSnapNilOnEmptyRows() {
        XCTAssertNil(snapCursorIndex(rows: [], currentKey: trackKey(title: "A", artist: "B")))
    }

    func testContinuationActionMapping() {
        XCTAssertEqual(continuationAction(for: .char("s")), .shuffle)
        XCTAssertEqual(continuationAction(for: .char("p")), .playlist)
        XCTAssertEqual(continuationAction(for: .char("x")), .quiet)
        XCTAssertNil(continuationAction(for: .char("q")))   // 'q' must stay quit, even with the menu up
        XCTAssertNil(continuationAction(for: .char("r")))   // 'r' was radio; no longer a continuation key
        XCTAssertNil(continuationAction(for: .up))
    }
}
