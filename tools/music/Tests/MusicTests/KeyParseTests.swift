// tools/music/Tests/MusicTests/KeyParseTests.swift
import XCTest
@testable import music

/// Scripted byte source for `KeyPress.ByteInput`. Each queue entry is either
/// a byte or `nil`; `nil` simulates `nextWithin` timing out (no byte arrived
/// within the ESC-disambiguation window). `next()` (the indefinite blocking
/// read) is only ever asked for the first byte of a keypress in these tests,
/// so it pops the same queue — a `nil` there would mean the scripted stream
/// ran out, which none of these tests exercise.
private final class ScriptedInput {
    private var queue: [UInt8?]

    init(_ queue: [UInt8?]) {
        self.queue = queue
    }

    func next() -> UInt8? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    func nextWithin(_ ms: Int32) -> UInt8? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }
}

final class KeyParseTests: XCTestCase {
    override func tearDown() {
        KeyPress.resetInputForTesting()
        super.tearDown()
    }

    private func script(_ bytes: [UInt8?]) {
        let scripted = ScriptedInput(bytes)
        KeyPress.input = KeyPress.ByteInput(next: scripted.next, nextWithin: scripted.nextWithin)
    }

    func testLoneEscapeReturnsEscape() {
        // ESC, then a timeout standing in for "no follow-up byte arrived".
        script([0x1B, nil])
        XCTAssertEqual(KeyPress.read(), .escape)
    }

    func testEscapeBracketA_ReturnsUp() {
        script([0x1B, 0x5B, 0x41])
        XCTAssertEqual(KeyPress.read(), .up)
    }

    func testEscapeThenX_ReturnsEscapeThenChar() {
        // seq1 ('x') is not '[' or 'O' — it belongs to the NEXT keypress, so
        // it must be pushed back and returned as a normal char on the
        // following read, not swallowed.
        script([0x1B, UInt8(ascii: "x")])
        XCTAssertEqual(KeyPress.read(), .escape)
        XCTAssertEqual(KeyPress.read(), .char("x"))
    }

    func testEscapeBracketTimeout_ReturnsEscape() {
        script([0x1B, 0x5B, nil])
        XCTAssertEqual(KeyPress.read(), .escape)
    }

    func testEscapeBracket5Tilde_ReturnsPageUp() {
        script([0x1B, 0x5B, UInt8(ascii: "5"), UInt8(ascii: "~")])
        XCTAssertEqual(KeyPress.read(), .pageUp)
    }

    func testEscapeOH_ReturnsHome() {
        script([0x1B, 0x4F, 0x48])
        XCTAssertEqual(KeyPress.read(), .home)
    }

    func testPlainCharQ() {
        script([UInt8(ascii: "q")])
        XCTAssertEqual(KeyPress.read(), .char("q"))
    }

    func testEnterUnchanged() {
        script([0x0D])
        XCTAssertEqual(KeyPress.read(), .enter)
    }

    func testSpaceUnchanged() {
        script([0x20])
        XCTAssertEqual(KeyPress.read(), .space)
    }
}
