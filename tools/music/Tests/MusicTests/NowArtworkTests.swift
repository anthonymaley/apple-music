// tools/music/Tests/MusicTests/NowArtworkTests.swift
// The Now tab's REST artwork fallback — its pure parts: the per-album cache
// key, the search-term ladder that absorbs Apple's flaky library search, and
// which song hit a playing track resolves to. The orchestration
// (lookupAlbumArtwork) is a thin syncRun wrapper over two REST reads and isn't
// unit-tested; its parsing halves are covered here and in SearchTests /
// LibraryAPITests.
import XCTest
@testable import music

final class NowArtworkTests: XCTestCase {

    private func song(_ id: String, _ title: String, _ artist: String, _ album: String) -> CatalogSong {
        CatalogSong(id: id, title: title, artist: artist, album: album)
    }

    // MARK: nowAlbumKey

    func testAlbumKeyPartitionsByAlbumAndArtist() {
        XCTAssertEqual(nowAlbumKey(album: "Crush", artist: "Floating Points"),
                       "Crush\u{0}Floating Points")
    }

    /// NUL separates precisely because no real album/artist name contains it —
    /// "A" + "B C" must not collide with "A B" + "C".
    func testAlbumKeyCannotCollideAcrossTheSeparator() {
        XCTAssertNotEqual(nowAlbumKey(album: "A", artist: "B C"),
                          nowAlbumKey(album: "A B", artist: "C"))
    }

    // MARK: librarySearchTerms — the exact-then-prefix ladder

    /// Live behavior this exists for: "The Baron Sleeps and Dreams" returns
    /// nothing from library search, but "The Baron" returns that very song.
    func testLongTitleYieldsExactThenTwoWordPrefix() {
        XCTAssertEqual(librarySearchTerms(forTitle: "The Baron Sleeps and Dreams"),
                       ["The Baron Sleeps and Dreams", "The Baron"])
    }

    /// A title no longer than the prefix has nothing to fall back to — one
    /// term, one request.
    func testTitleAtOrUnderPrefixLengthYieldsExactlyOneTerm() {
        XCTAssertEqual(librarySearchTerms(forTitle: "Crush"), ["Crush"])
        XCTAssertEqual(librarySearchTerms(forTitle: "Barely Legal"), ["Barely Legal"])
    }

    /// The repro track. Its exact term resolves live, so the second term is
    /// never requested — the ladder stops at the first hit — but it is still
    /// offered, because a title being short is no guarantee search matches it.
    func testReproTitleOffersExactFirstThenAPrefix() {
        XCTAssertEqual(librarySearchTerms(forTitle: "Push It Along"), ["Push It Along", "Push It"])
    }

    func testTitleIsTrimmedAndEmptyYieldsNoTerms() {
        XCTAssertEqual(librarySearchTerms(forTitle: "  Basefree  "), ["Basefree"])
        XCTAssertEqual(librarySearchTerms(forTitle: "   "), [])
        XCTAssertEqual(librarySearchTerms(forTitle: ""), [])
    }

    func testPrefixWordCountIsConfigurable() {
        XCTAssertEqual(librarySearchTerms(forTitle: "The Bartender And The Thief", prefixWords: 3),
                       ["The Bartender And The Thief", "The Bartender And"])
    }

    // MARK: bestSongMatch — album disambiguation

    /// A track on both a single and an LP must resolve to the album that is
    /// actually playing — live, "Barely Legal" really does return three hits
    /// across two albums.
    func testPrefersTheHitWhoseAlbumAlsoMatches() {
        let hits = [
            song("i.1", "Barely Legal", "Strokes, The", "Pepsi Music Hall 2002"),
            song("i.2", "Barely Legal", "Strokes, The", "Is This It"),
        ]
        let m = bestSongMatch(hits, title: "Barely Legal", artist: "Strokes, The", album: "Is This It")
        XCTAssertEqual(m?.id, "i.2", "must not take the first same-artist hit when a better album match exists")
    }

    /// Music's album string and the library's can differ; the right song by the
    /// right artist is still the right cover source.
    func testFallsBackToArtistMatchWhenAlbumStringDiffers() {
        let hits = [song("i.3", "Push It Along", "A Tribe Called Quest", "People's Instinctive Travels a")]
        let m = bestSongMatch(hits, title: "Push It Along", artist: "A Tribe Called Quest",
                              album: "People's Instinctive Travels and the Paths of Rhythm")
        XCTAssertEqual(m?.id, "i.3")
    }

    func testMatchIsCaseAndWhitespaceInsensitive() {
        let hits = [song("i.4", " PUSH It Along ", "a tribe called QUEST", "PEOPLE'S Instinctive Travels a")]
        let m = bestSongMatch(hits, title: "Push It Along", artist: "A Tribe Called Quest",
                              album: "People's Instinctive Travels a")
        XCTAssertEqual(m?.id, "i.4")
    }

    // MARK: bestSongMatch — refusals (a gradient beats someone else's cover)

    func testRefusesSameTitleByAnotherArtist() {
        let hits = [song("i.5", "Push It Along", "Someone Else", "Their Album")]
        XCTAssertNil(bestSongMatch(hits, title: "Push It Along", artist: "A Tribe Called Quest",
                                   album: "People's Instinctive Travels a"),
                     "a same-titled song by the WRONG artist must never supply the cover")
    }

    func testRefusesDifferentTitleBySameArtist() {
        let hits = [song("i.6", "Can I Kick It?", "A Tribe Called Quest", "People's Instinctive Travels a")]
        XCTAssertNil(bestSongMatch(hits, title: "Push It Along", artist: "A Tribe Called Quest",
                                   album: "People's Instinctive Travels a"))
    }

    func testRefusesEmptyCandidatesAndEmptyArtist() {
        XCTAssertNil(bestSongMatch([], title: "X", artist: "Y", album: "Z"))
        // An empty artist can't disambiguate, so every hit would "match".
        XCTAssertNil(bestSongMatch([song("i.7", "X", "", "Z")], title: "X", artist: "", album: "Z"))
    }

    // MARK: the relationship path + parsing this route depends on

    func testLibrarySongAlbumsPathShape() {
        XCTAssertEqual(librarySongAlbumsPath(songID: "i.gekAdip2Olb6"),
                       "/v1/me/library/songs/i.gekAdip2Olb6/albums")
    }

    /// The live response shape for the repro: the song's albums relationship
    /// returns the same library album (id + {w}x{h} template) the Library tab
    /// gets from libraryAlbums(), and resolveURL turns it into a real CDN URL.
    func testSongAlbumsRelationshipParsesToTheLibraryTabsCover() {
        let json = """
        {"data":[{"id":"l.Lr0fKV6","type":"library-albums","attributes":{
          "artistName":"A Tribe Called Quest","name":"People's Instinctive Travels a","trackCount":14,
          "artwork":{"height":1200,"width":1200,
            "url":"https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/97/dj.rgkkvazm.jpg/{w}x{h}bb.jpg"}}}]}
        """.data(using: .utf8)!
        let album = parseLibraryAlbums(from: json).first
        XCTAssertEqual(album?.id, "l.Lr0fKV6")
        XCTAssertEqual(ArtworkStore.resolveURL(album?.artworkURL ?? "", width: 300, height: 300),
                       "https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/97/dj.rgkkvazm.jpg/300x300bb.jpg")
    }

    /// The album id doubles as the ArtworkStore key, so Now and the Library tab
    /// must land on the SAME on-disk cache entry for the same album — that
    /// shared key is what makes them one artwork source rather than two.
    func testAlbumIDCacheKeyIsSharedWithTheLibraryTab() {
        XCTAssertEqual(ArtworkStore.cacheKey("l.Lr0fKV6"), "l_Lr0fKV6")
    }

    // MARK: library-search song shape the lookup consumes

    func testLibrarySongSearchParsesIDArtistAndAlbum() {
        let json = """
        {"results":{"library-songs":{"data":[{"id":"i.gekAdip2Olb6","attributes":{
          "name":"Push It Along","artistName":"A Tribe Called Quest",
          "albumName":"People's Instinctive Travels a"}}]}}}
        """.data(using: .utf8)!
        let hits = parseSearchResults(from: json, types: [.songs], library: true).songs
        XCTAssertEqual(hits.first?.id, "i.gekAdip2Olb6")
        // The whole route hinges on these two fields being present to match on.
        XCTAssertEqual(hits.first?.artist, "A Tribe Called Quest")
        XCTAssertEqual(hits.first?.album, "People's Instinctive Travels a")
        XCTAssertNotNil(bestSongMatch(hits, title: "Push It Along", artist: "A Tribe Called Quest",
                                      album: "People's Instinctive Travels a"))
    }
}
