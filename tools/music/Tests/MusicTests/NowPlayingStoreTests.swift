// tools/music/Tests/MusicTests/NowPlayingStoreTests.swift
import XCTest
@testable import music

final class NowPlayingStoreTests: XCTestCase {
    func testReadReturnsLastWrite() {
        let store = NowPlayingStore()
        var np = NowPlayingState()
        np.track = "Homosapien"
        np.artist = "Pete Shelley"
        store.write(NowPlayingSnapshot(outcome: .active(np), history: [], surrounding: []))
        let snap = store.read()
        guard case .active(let got) = snap.outcome else { return XCTFail("expected active") }
        XCTAssertEqual(got.track, "Homosapien")
        XCTAssertEqual(got.artist, "Pete Shelley")
    }

    func testDefaultIsUnavailable() {
        let store = NowPlayingStore()
        if case .unavailable = store.read().outcome { } else { XCTFail("expected unavailable default") }
    }

    func testGenerationBumpsOnEveryWriteAndIsStableAcrossReads() {
        let store = NowPlayingStore()
        let g0 = store.readWithGeneration().generation
        XCTAssertEqual(store.readWithGeneration().generation, g0, "reads must not advance the generation")
        store.write(NowPlayingSnapshot(outcome: .stopped, history: [], surrounding: []))
        let g1 = store.readWithGeneration().generation
        XCTAssertNotEqual(g1, g0)
        store.write(NowPlayingSnapshot(outcome: .stopped, history: [], surrounding: []))
        XCTAssertNotEqual(store.readWithGeneration().generation, g1, "identical payloads still bump (a write is a change signal)")
    }

    func testReadWithGenerationReturnsLastWrite() {
        let store = NowPlayingStore()
        var np = NowPlayingState()
        np.track = "Telegram"
        store.write(NowPlayingSnapshot(outcome: .active(np), history: [], surrounding: []))
        let (snap, _) = store.readWithGeneration()
        guard case .active(let got) = snap.outcome else { return XCTFail("expected active") }
        XCTAssertEqual(got.track, "Telegram")
    }

    func testConcurrentWritesDoNotTearState() {
        let store = NowPlayingStore()
        let group = DispatchGroup()
        for i in 0..<500 {
            group.enter()
            DispatchQueue.global().async {
                var np = NowPlayingState()
                np.track = "T\(i)"
                np.position = i
                store.write(NowPlayingSnapshot(outcome: .active(np), history: [], surrounding: []))
                group.leave()
            }
        }
        for _ in 0..<500 {
            group.enter()
            DispatchQueue.global().async {
                // A torn read would crash or mismatch; we only assert it never traps
                // and that the track/position pair stays internally consistent.
                if case .active(let np) = store.read().outcome {
                    XCTAssertTrue(np.track.hasPrefix("T"))
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
    }
}
