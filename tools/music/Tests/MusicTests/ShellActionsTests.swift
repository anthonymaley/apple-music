// tools/music/Tests/MusicTests/ShellActionsTests.swift
import XCTest
@testable import music

final class ShellActionsTests: XCTestCase {
    // MARK: - StatusStore

    func testToastVisibleUntilExpiryThenClears() {
        let store = StatusStore()
        let t0 = Date(timeIntervalSince1970: 1000)
        store.post("Saved.", now: t0)
        XCTAssertEqual(store.current(now: t0)?.text, "Saved.")
        XCTAssertEqual(store.current(now: t0.addingTimeInterval(2.9))?.text, "Saved.")
        XCTAssertNil(store.current(now: t0.addingTimeInterval(3.0)))
        // Expiry clears the stored toast, not just the returned value.
        XCTAssertNil(store.current(now: t0))
    }

    func testNewerPostReplacesOlder() {
        let store = StatusStore()
        let t0 = Date(timeIntervalSince1970: 1000)
        store.post("first", now: t0)
        store.post("second", error: true, now: t0.addingTimeInterval(1))
        let t = store.current(now: t0.addingTimeInterval(2))
        XCTAssertEqual(t?.text, "second")
        XCTAssertEqual(t?.isError, true)
    }

    func testNoToastByDefault() {
        XCTAssertNil(StatusStore().current())
    }

    // MARK: - DeltaAccumulator (coalesced relative volume)

    func testDeltaAccumulatesAndTakesOnce() {
        let acc = DeltaAccumulator()
        acc.add(5); acc.add(5); acc.add(-5)
        XCTAssertEqual(acc.take(), 5)
        XCTAssertEqual(acc.take(), 0, "second take must see nothing left to apply")
    }

    // MARK: - TargetAccumulator (coalesced absolute per-speaker volume)

    func testTargetKeepsLatestPerKeyAndTakesOnce() {
        let acc = TargetAccumulator()
        acc.set("Kitchen", 40)
        acc.set("Kitchen", 45)
        acc.set("Deck", 60)
        XCTAssertEqual(acc.take("Kitchen"), 45)
        XCTAssertNil(acc.take("Kitchen"), "superseded/applied targets must not re-apply")
        XCTAssertEqual(acc.take("Deck"), 60)
    }

    // MARK: - ActionRunner

    func testRunnerPostsActionErrorMessageOnFailure() {
        let status = StatusStore()
        let runner = ActionRunner(status: status)
        let done = expectation(description: "action ran")
        runner.run("Play") {
            defer { done.fulfill() }
            try require(false, "Couldn't play that track.")
        }
        wait(for: [done], timeout: 2)
        // The toast is posted after the body returns; poll briefly for it.
        let deadline = Date().addingTimeInterval(1)
        while status.current() == nil && Date() < deadline { usleep(10_000) }
        XCTAssertEqual(status.current()?.text, "Couldn't play that track.")
        XCTAssertEqual(status.current()?.isError, true)
    }

    func testRunnerRunsSeriallyInOrder() {
        let status = StatusStore()
        let runner = ActionRunner(status: status)
        let lock = NSLock()
        var order: [Int] = []
        let done = expectation(description: "all ran")
        done.expectedFulfillmentCount = 3
        for i in 1...3 {
            runner.run("op\(i)") {
                lock.lock(); order.append(i); lock.unlock()
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(order, [1, 2, 3])
    }
}
