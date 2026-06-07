// tools/music/Tests/MusicTests/ShellFrameTests.swift
import XCTest
@testable import music

final class ShellFrameTests: XCTestCase {
    func testFullTier() {
        let f = shellLayout(width: 120, height: 40)
        XCTAssertEqual(f.barTier, .full)
        XCTAssertEqual(f.barHeight, 3)
        XCTAssertEqual(f.tabStyle, .full)
        XCTAssertEqual(f.footerY, 40)
        XCTAssertEqual(f.barY, 37)          // footerY - barHeight
        XCTAssertEqual(f.bodyY, 4)          // label(1) tabs(2) rule(3) body(4)
        XCTAssertEqual(f.bodyHeight, f.barY - f.bodyY) // 33
        XCTAssertGreaterThan(f.bodyHeight, 0)
    }

    func testCompactTier() {
        let f = shellLayout(width: 120, height: 21)
        XCTAssertEqual(f.barTier, .compact)
        XCTAssertEqual(f.barHeight, 1)
        XCTAssertEqual(f.tabStyle, .full)
    }

    func testMinimalTier() {
        let f = shellLayout(width: 120, height: 16)
        XCTAssertEqual(f.barTier, .minimal)
        XCTAssertEqual(f.barHeight, 1)
        XCTAssertEqual(f.tabStyle, .digits)
    }

    func testBareTier() {
        let f = shellLayout(width: 120, height: 12)
        XCTAssertEqual(f.barTier, .bare)
        XCTAssertEqual(f.barHeight, 0)
        XCTAssertEqual(f.tabStyle, .hidden)
        XCTAssertEqual(f.bodyY, 3)          // label(1) rule(2) body(3) — no tab row
    }

    func testBodyHeightNeverNegative() {
        for h in 1...50 {
            XCTAssertGreaterThanOrEqual(shellLayout(width: 80, height: h).bodyHeight, 0)
        }
    }
}
