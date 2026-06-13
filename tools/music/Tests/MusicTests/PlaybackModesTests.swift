import XCTest
@testable import music

final class PlaybackModesTests: XCTestCase {
    func testShuffleModeCycle() {
        XCTAssertEqual(ShuffleMode.songs.next, .albums)
        XCTAssertEqual(ShuffleMode.albums.next, .groupings)
        XCTAssertEqual(ShuffleMode.groupings.next, .songs)
    }

    func testRepeatModeCycle() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }

    func testParseModes() {
        XCTAssertEqual(parsePlaybackModes("true,albums,all"),
                       PlaybackModes(shuffleEnabled: true, shuffleMode: .albums, songRepeat: .all))
        XCTAssertEqual(parsePlaybackModes(" false , songs , off "),
                       PlaybackModes(shuffleEnabled: false, shuffleMode: .songs, songRepeat: .off))
    }

    func testParseModesRejectsGarbage() {
        XCTAssertNil(parsePlaybackModes("nope"))
        XCTAssertNil(parsePlaybackModes("true,jazz,all"))   // unknown shuffle mode
        XCTAssertNil(parsePlaybackModes("true,songs,sometimes")) // unknown repeat
    }
}
