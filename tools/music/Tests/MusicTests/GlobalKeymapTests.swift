// tools/music/Tests/MusicTests/GlobalKeymapTests.swift
import XCTest
@testable import music

final class GlobalKeymapTests: XCTestCase {
    func testTransportKeys() {
        XCTAssertEqual(resolveGlobalKey(.space), .playPause)
        XCTAssertEqual(resolveGlobalKey(.char("+")), .volumeUp)
        XCTAssertEqual(resolveGlobalKey(.char("=")), .volumeUp)
        XCTAssertEqual(resolveGlobalKey(.char("-")), .volumeDown)
        XCTAssertEqual(resolveGlobalKey(.char(">")), .next)
        XCTAssertEqual(resolveGlobalKey(.char(".")), .next)
        XCTAssertEqual(resolveGlobalKey(.f9), .next)
        XCTAssertEqual(resolveGlobalKey(.char("<")), .prev)
        XCTAssertEqual(resolveGlobalKey(.f7), .prev)
        XCTAssertEqual(resolveGlobalKey(.char("z")), .shuffle)
        XCTAssertEqual(resolveGlobalKey(.char("r")), .radio)
        XCTAssertEqual(resolveGlobalKey(.char("q")), .quit)
    }
    func testDigitsSwitchScene() {
        XCTAssertEqual(resolveGlobalKey(.char("1")), .switchScene(1))
        XCTAssertEqual(resolveGlobalKey(.char("3")), .switchScene(3))
    }
    func testZeroIsNotASwitch() {
        XCTAssertNil(resolveGlobalKey(.char("0")))
    }
    func testNonGlobalKeysReturnNil() {
        XCTAssertNil(resolveGlobalKey(.up))
        XCTAssertNil(resolveGlobalKey(.enter))
        XCTAssertNil(resolveGlobalKey(.char("/")))
    }
}
