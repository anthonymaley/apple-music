// tools/music/Tests/MusicTests/PlaybackContextTests.swift
import XCTest
@testable import music

final class PlaybackContextTests: XCTestCase {
    func testParsesWindowMarksCurrentByIndex() {
        // Format: "name\ncurrentIndex\ntotal\nwindowStart\nidx|title|artist..."
        let raw = "Friday Mix\n3\n42\n2\n2|Song B|Artist B\n3|Song C|Artist C\n4|Song C|Artist C"
        let q = parseContextQueue(raw)
        XCTAssertEqual(q.name, "Friday Mix")
        XCTAssertEqual(q.currentIndex, 3)
        XCTAssertEqual(q.total, 42)
        XCTAssertEqual(q.tracks.count, 3)
        XCTAssertEqual(q.tracks[1].index, 3)
        XCTAssertTrue(q.tracks[1].isCurrent)
        XCTAssertFalse(q.tracks[2].isCurrent)
    }
    func testEmptyOnMalformed() {
        let q = parseContextQueue("")
        XCTAssertEqual(q.name, "")
        XCTAssertTrue(q.tracks.isEmpty)
    }
}
