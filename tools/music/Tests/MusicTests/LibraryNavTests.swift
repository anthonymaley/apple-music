// tools/music/Tests/MusicTests/LibraryNavTests.swift
import XCTest
@testable import music

final class LibraryNavTests: XCTestCase {
    private let albumSel = LibrarySelection(id: "l.aaa", primary: "Kid A", secondary: "Radiohead")

    func testStartsOnAlbumsRoot() {
        let s = LibraryNav.initial
        XCTAssertEqual(s.subView, .albums)
        XCTAssertEqual(s.current, .albumList)
        XCTAssertEqual(s.cursor, 0)
    }

    func testDownMovesCursorClamped() {
        var (s, _) = libraryReduce(.initial, .down, itemCount: 2, selection: albumSel)
        XCTAssertEqual(s.cursor, 1)
        (s, _) = libraryReduce(s, .down, itemCount: 2, selection: albumSel)  // clamp at last
        XCTAssertEqual(s.cursor, 1)
    }

    func testSwitchNextGoesToArtistsRootResettingCursor() {
        var (s, _) = libraryReduce(.initial, .down, itemCount: 5, selection: albumSel)
        (s, _) = libraryReduce(s, .switchNext, itemCount: 5, selection: albumSel)
        XCTAssertEqual(s.subView, .artists)
        XCTAssertEqual(s.current, .artistList)
        XCTAssertEqual(s.cursor, 0)
    }

    func testEnterOnAlbumListPushesTracksAndFetches() {
        let (s, action) = libraryReduce(.initial, .enter, itemCount: 2, selection: albumSel)
        XCTAssertEqual(s.current, .tracks(albumID: "l.aaa", albumTitle: "Kid A", artist: "Radiohead"))
        XCTAssertEqual(action, .fetchAlbumTracks(albumID: "l.aaa", albumTitle: "Kid A", artist: "Radiohead"))
    }

    func testBackPopsToAlbumRoot() {
        var (s, _) = libraryReduce(.initial, .enter, itemCount: 2, selection: albumSel)
        (s, _) = libraryReduce(s, .back, itemCount: 10, selection: nil)
        XCTAssertEqual(s.current, .albumList)
    }

    func testPlayOnAlbumListEmitsAlbumPlay() {
        let (_, action) = libraryReduce(.initial, .play, itemCount: 2, selection: albumSel)
        XCTAssertEqual(action, .play(.album(id: "l.aaa", title: "Kid A", artist: "Radiohead")))
    }

    func testShuffleOnAlbumListEmitsAlbumShuffle() {
        let (_, action) = libraryReduce(.initial, .shuffle, itemCount: 2, selection: albumSel)
        XCTAssertEqual(action, .shuffle(.album(id: "l.aaa", title: "Kid A", artist: "Radiohead")))
    }

    func testArtistsEnterDrillsToArtistAlbums() {
        var s = LibraryNav.initial
        (s, _) = libraryReduce(s, .switchNext, itemCount: 3, selection: nil)  // → artists
        let artistSel = LibrarySelection(id: "r.1", primary: "Radiohead", secondary: "")
        let (s2, action) = libraryReduce(s, .enter, itemCount: 3, selection: artistSel)
        XCTAssertEqual(s2.current, .artistAlbums(artistID: "r.1", artistName: "Radiohead"))
        XCTAssertEqual(action, .fetchArtistAlbums(artistID: "r.1", artistName: "Radiohead"))
    }

    func testShuffleOnArtistListEmitsArtistShuffle() {
        var s = LibraryNav.initial
        (s, _) = libraryReduce(s, .switchNext, itemCount: 3, selection: nil)
        let artistSel = LibrarySelection(id: "r.1", primary: "Radiohead", secondary: "")
        let (_, action) = libraryReduce(s, .shuffle, itemCount: 3, selection: artistSel)
        XCTAssertEqual(action, .shuffle(.artist(id: "r.1", name: "Radiohead")))
    }

    func testSongsEnterPlaysTheSong() {
        var s = LibraryNav.initial
        (s, _) = libraryReduce(s, .switchPrev, itemCount: 3, selection: nil)  // albums → songs (wrap back)
        XCTAssertEqual(s.subView, .songs)
        let songSel = LibrarySelection(id: "i.s1", primary: "Idioteque", secondary: "Radiohead")
        let (_, action) = libraryReduce(s, .enter, itemCount: 3, selection: songSel)
        XCTAssertEqual(action, .play(.song(id: "i.s1", title: "Idioteque", artist: "Radiohead")))
    }
}
