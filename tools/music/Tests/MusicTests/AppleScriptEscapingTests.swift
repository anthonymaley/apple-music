import XCTest
@testable import music

final class AppleScriptEscapingTests: XCTestCase {
    func testPlainStringUnchanged() {
        XCTAssertEqual(escapeAppleScriptString("Hello World"), "Hello World")
    }

    func testEscapesDoubleQuote() {
        // say "hi"  ->  say \"hi\"
        XCTAssertEqual(escapeAppleScriptString("say \"hi\""), "say \\\"hi\\\"")
    }

    func testEscapesBackslash() {
        // AC\DC  ->  AC\\DC   (the bug: backslash was previously left untouched)
        XCTAssertEqual(escapeAppleScriptString("AC\\DC"), "AC\\\\DC")
    }

    func testBackslashEscapedBeforeQuote() {
        // A literal backslash followed by a quote must become an escaped
        // backslash followed by an escaped quote. If the quote were escaped
        // first, the backslash it introduces would be doubled incorrectly.
        // input:  \"   (2 chars: backslash, quote)
        // output: \\\" (4 chars: esc-backslash, esc-quote)
        XCTAssertEqual(escapeAppleScriptString("\\\""), "\\\\\\\"")
    }

    func testEmptyString() {
        XCTAssertEqual(escapeAppleScriptString(""), "")
    }
}
