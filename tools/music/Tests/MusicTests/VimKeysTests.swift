// tools/music/Tests/MusicTests/VimKeysTests.swift
import XCTest
@testable import music

final class VimKeysTests: XCTestCase {
    func testJKHMapRegardlessOfListScene() {
        for listScene in [true, false] {
            XCTAssertEqual(vimAlias(.char("j"), listScene: listScene), .down)
            XCTAssertEqual(vimAlias(.char("k"), listScene: listScene), .up)
            XCTAssertEqual(vimAlias(.char("h"), listScene: listScene), .left)
        }
    }

    func testLMapsToRightOnlyWhenListScene() {
        XCTAssertEqual(vimAlias(.char("l"), listScene: true), .right)
        XCTAssertEqual(vimAlias(.char("l"), listScene: false), .char("l"))
    }

    func testGAndCapitalGMapToHomeEndOnlyWhenListScene() {
        XCTAssertEqual(vimAlias(.char("g"), listScene: true), .home)
        XCTAssertEqual(vimAlias(.char("G"), listScene: true), .end)
        XCTAssertEqual(vimAlias(.char("g"), listScene: false), .char("g"))
        XCTAssertEqual(vimAlias(.char("G"), listScene: false), .char("G"))
    }

    func testCtrlDAndCtrlUMapToPageDownUp() {
        // Control bytes arrive from Terminal.swift's parseKey() as .char wrapping
        // the raw control-code Unicode scalar (0x04 / 0x15) — verified by reading
        // parseKey's byte switch, which has no special case for these bytes.
        XCTAssertEqual(vimAlias(.char("\u{04}"), listScene: true), .pageDown)
        XCTAssertEqual(vimAlias(.char("\u{15}"), listScene: true), .pageUp)
        XCTAssertEqual(vimAlias(.char("\u{04}"), listScene: false), .pageDown)
        XCTAssertEqual(vimAlias(.char("\u{15}"), listScene: false), .pageUp)
    }

    func testUnrelatedKeysPassThroughUnchanged() {
        XCTAssertEqual(vimAlias(.char("p"), listScene: true), .char("p"))
        XCTAssertEqual(vimAlias(.char("p"), listScene: false), .char("p"))
        XCTAssertEqual(vimAlias(.enter, listScene: true), .enter)
        XCTAssertEqual(vimAlias(.enter, listScene: false), .enter)
        XCTAssertEqual(vimAlias(.up, listScene: true), .up)
        XCTAssertEqual(vimAlias(.pageDown, listScene: true), .pageDown)
    }
}
