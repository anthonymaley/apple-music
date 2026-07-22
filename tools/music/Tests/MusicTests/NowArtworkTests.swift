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

    private func catalogAlbum(_ id: String, _ name: String, _ artist: String, artworkURL: String? = nil) -> CatalogAlbum {
        CatalogAlbum(id: id, name: name, artist: artist, artworkURL: artworkURL)
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

    // MARK: libraryAlbumSearchTerms — route 4's term policy

    /// The repro album, live-validated 2026-07-21: "instinctive" alone
    /// resolves the album search, so it must sort ahead of the rest.
    func testStripsPunctuationKeepsWordsOverThreeCharsLongestFirst() {
        XCTAssertEqual(libraryAlbumSearchTerms(forAlbum: "People's Instinctive Travels a"),
                       ["Instinctive", "People's"])
    }

    /// A trailing comma or wrapping parens would make the token unmatchable —
    /// stripped before the length filter, not after (so "Sleeps," still
    /// counts as length 6, not 7).
    func testStripsLeadingAndTrailingPunctuationPerWord() {
        XCTAssertEqual(libraryAlbumSearchTerms(forAlbum: "Sleeps, and (Dreams)"),
                       ["Sleeps", "Dreams"])
    }

    /// "a", "and", "of" — anything len <= 3 carries no search signal and is
    /// dropped outright, not merely deprioritized.
    func testDropsWordsOfLengthThreeOrLess() {
        XCTAssertEqual(libraryAlbumSearchTerms(forAlbum: "Cool Jam Vibe"), ["Cool", "Vibe"])
    }

    /// More than two qualifying words: only the two longest survive, one
    /// request each, matching route 3's two-request ceiling.
    func testCapsAtTheTwoLongestWords() {
        XCTAssertEqual(libraryAlbumSearchTerms(forAlbum: "Instinctive Travels Along Pathways"),
                       ["Instinctive", "Pathways"])
    }

    /// An album name with only one word long enough to qualify yields exactly
    /// one term rather than padding to two.
    func testOneQualifyingWordYieldsOneTerm() {
        XCTAssertEqual(libraryAlbumSearchTerms(forAlbum: "Is This It"), ["This"])
    }

    /// Every word too short (or no words at all) yields no terms — the album
    /// route is skipped rather than searching on noise.
    func testNoQualifyingWordsYieldsNoTerms() {
        XCTAssertEqual(libraryAlbumSearchTerms(forAlbum: "Is It A"), [])
        XCTAssertEqual(libraryAlbumSearchTerms(forAlbum: ""), [])
    }

    // MARK: bestAlbumMatch — album disambiguation (route 4 has no title to lean on)

    func testBestAlbumMatchRequiresArtistAndAlbumBothToMatch() {
        let hits = [catalogAlbum("l.1", "People's Instinctive Travels a", "A Tribe Called Quest")]
        let m = bestAlbumMatch(hits, artist: "A Tribe Called Quest", album: "People's Instinctive Travels a")
        XCTAssertEqual(m?.id, "l.1")
    }

    func testBestAlbumMatchIsCaseAndWhitespaceInsensitive() {
        let hits = [catalogAlbum("l.2", " PEOPLE'S Instinctive Travels a ", "a tribe called QUEST")]
        let m = bestAlbumMatch(hits, artist: "A Tribe Called Quest", album: "People's Instinctive Travels a")
        XCTAssertEqual(m?.id, "l.2")
    }

    // MARK: bestAlbumMatch — refusals (a gradient beats wrong art)

    func testBestAlbumMatchRefusesArtistMismatch() {
        let hits = [catalogAlbum("l.3", "People's Instinctive Travels a", "Someone Else")]
        XCTAssertNil(bestAlbumMatch(hits, artist: "A Tribe Called Quest", album: "People's Instinctive Travels a"),
                     "a same-named album by the WRONG artist must never supply the cover")
    }

    func testBestAlbumMatchRefusesAlbumNameMismatch() {
        let hits = [catalogAlbum("l.4", "Midnight Marauders", "A Tribe Called Quest")]
        XCTAssertNil(bestAlbumMatch(hits, artist: "A Tribe Called Quest", album: "People's Instinctive Travels a"),
                     "route 4 has no title to disambiguate on, so the album name itself must match")
    }

    func testBestAlbumMatchRefusesEmptyCandidatesAndEmptyArtistOrAlbum() {
        XCTAssertNil(bestAlbumMatch([], artist: "X", album: "Y"))
        XCTAssertNil(bestAlbumMatch([catalogAlbum("l.5", "Y", "")], artist: "", album: "Y"))
        XCTAssertNil(bestAlbumMatch([catalogAlbum("l.6", "", "X")], artist: "X", album: ""))
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

    // MARK: library-search album shape route 4 consumes

    /// Route 4 needs artwork out of a library-ALBUMS search response, not just
    /// id/name/artist — the same `attributes.artwork.url` field
    /// `parseLibraryAlbums` already reads (verified live 2026-07-21, see file
    /// header). Without this, every album match would look artless.
    func testLibraryAlbumSearchParsesIDArtistNameAndArtwork() {
        let json = """
        {"results":{"library-albums":{"data":[{"id":"l.Lr0fKV6","attributes":{
          "name":"People's Instinctive Travels a","artistName":"A Tribe Called Quest",
          "artwork":{"height":1200,"width":1200,
            "url":"https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/97/dj.rgkkvazm.jpg/{w}x{h}bb.jpg"}}}]}}}
        """.data(using: .utf8)!
        let hits = parseSearchResults(from: json, types: [.albums], library: true).albums
        XCTAssertEqual(hits.first?.id, "l.Lr0fKV6")
        XCTAssertEqual(hits.first?.artist, "A Tribe Called Quest")
        XCTAssertEqual(hits.first?.name, "People's Instinctive Travels a")
        XCTAssertNotNil(bestAlbumMatch(hits, artist: "A Tribe Called Quest",
                                       album: "People's Instinctive Travels a"))
        XCTAssertEqual(ArtworkStore.resolveURL(hits.first?.artworkURL ?? "", width: 300, height: 300),
                       "https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/97/dj.rgkkvazm.jpg/300x300bb.jpg")
    }

    /// No artwork attribute at all (the 8/40 rips-with-no-cover case, file
    /// header) must parse to nil, not an empty string a URL-builder would
    /// silently mangle.
    func testLibraryAlbumSearchWithNoArtworkParsesToNilArtworkURL() {
        let json = """
        {"results":{"library-albums":{"data":[{"id":"l.abc","attributes":{
          "name":"Some Live Recording","artistName":"Some Artist"}}]}}}
        """.data(using: .utf8)!
        let hits = parseSearchResults(from: json, types: [.albums], library: true).albums
        XCTAssertNil(hits.first?.artworkURL)
    }
}
