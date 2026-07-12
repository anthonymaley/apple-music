// tools/music/Tests/MusicTests/LibraryAPITests.swift
import XCTest
@testable import music

final class LibraryAPITests: XCTestCase {
    func testAlbumsPath() {
        XCTAssertEqual(libraryAlbumsPath(limit: 100, offset: 0),
                       "/v1/me/library/albums?limit=100&offset=0")
        XCTAssertEqual(libraryAlbumsPath(limit: 25, offset: 50),
                       "/v1/me/library/albums?limit=25&offset=50")
    }

    func testParsesLibraryAlbums() {
        let r = parseLibraryAlbums(from: Data(Self.albums.utf8))
        XCTAssertEqual(r.map(\.name), ["Kid A", "OK Computer"])
        XCTAssertEqual(r.first?.artist, "Radiohead")
        XCTAssertEqual(r.first?.id, "l.aaa")
    }

    func testParsesEmptyAndGarbage() {
        XCTAssertTrue(parseLibraryAlbums(from: Data("{}".utf8)).isEmpty)
        XCTAssertTrue(parseLibraryAlbums(from: Data("nope".utf8)).isEmpty)
    }

    static let albums = """
    { "data": [
      { "id": "l.aaa", "attributes": { "name": "Kid A", "artistName": "Radiohead" } },
      { "id": "l.bbb", "attributes": { "name": "OK Computer", "artistName": "Radiohead" } }
    ] }
    """
}
