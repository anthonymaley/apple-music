# Playlist Browser Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the `music playlist` browser from a flat 2-pane list into a 3-zone surface (rail · hero · preview) with truthful, progressively-loaded metadata and a stable, flicker-free layout.

**Architecture:** A pure, unit-testable model layer (`PlaylistBrowserModel.swift`: zone geometry, badge derivation, duration formatting, enrichment-queue selection, gradient seeding, rail-row truncation) drives a thin render/loop in `runPlaylistBrowser`. Metadata enrichment is tick-driven on the existing single-threaded event loop (no background thread). Data fetches (AppleScript) live in the caller (`PlaylistCommands.swift`) and are injected as closures, keeping the UI layer pure and testable.

**Tech Stack:** Swift (ArgumentParser CLI), AppleScript over `osascript` via `syncRun`, XCTest. Terminal rendering via ANSI escape codes.

**Spec:** `docs/superpowers/specs/2026-06-06-playlist-browser-redesign-design.md`

**Branch note:** This project commits directly to `main` (its established convention — see `git log`). No worktree. Commit after each task.

**Verification reality:** The live TUI cannot be exercised in CI. Pure-model tasks (1–2) are full TDD. Rendering/loop tasks (4–9) are build-verified (`swift build` clean + `swift test` still green) and then **manually verified by the user** running `music playlist`. Each rendering task lists its manual-verification checklist; do not mark the feature "done" on a green build alone.

---

## File Structure

- **Create** `tools/music/Sources/TUI/PlaylistBrowserModel.swift` — pure model: `PlaylistMeta`, `PlaylistBadge`, `badge(name:isSmart:specialKind:)`, `formatPlaylistDuration(_:)`, `PlaylistZones`/`playlistZones(width:)`, `nextEnrichmentBatch(total:loaded:visible:batchSize:)`, `gradientBlock(name:width:height:)`, `railName(_:nameWidth:)`. No I/O, no ANSI side effects beyond returning strings.
- **Create** `tools/music/Tests/MusicTests/PlaylistBrowserModelTests.swift` — unit tests for every pure function above.
- **Modify** `tools/music/Sources/TUI/Terminal.swift` — add `brightWhite`, `lime`, `amber` to `ANSICode`.
- **Modify** `tools/music/Sources/TUI/ListPicker.swift` — rewrite `runPlaylistBrowser` to the 3-zone, enrichment-driven design. New closures `onMeta`, `onPreview` added to its signature alongside existing `onTracks`.
- **Modify** `tools/music/Sources/Commands/PlaylistCommands.swift` — provide `onMeta` (batched count/duration/smart/specialKind for a set of indices) and `onPreview` (light 8-track fetch); pass them to `runPlaylistBrowser`.

Existing helpers reused: `renderShell`, `clearBody`, `truncText`, `ScreenFrame`, `BrowserState`, `BrowserFocus`, `BrowserResult`, `PlaybackContext`, `PlaylistPreview`.

---

## Task 1: Color roles in ANSICode

**Files:**
- Modify: `tools/music/Sources/TUI/Terminal.swift:22` (after `yellow`)

- [ ] **Step 1: Add the three palette roles**

In `struct ANSICode`, after the `yellow` line, add:

```swift
    static let brightWhite = "\u{1B}[97m"
    static let lime = "\u{1B}[92m"
    static let amber = "\u{1B}[38;2;255;176;0m"
```

- [ ] **Step 2: Build**

Run: `cd tools/music && swift build`
Expected: `Build complete!` (ignore stale `.pcm` cache warnings).

- [ ] **Step 3: Commit**

```bash
git add tools/music/Sources/TUI/Terminal.swift
git commit -m "feat(tui): add brightWhite/lime/amber palette roles"
```

---

## Task 2: Pure model layer (`PlaylistBrowserModel.swift`)

Build the testable core first, TDD. All functions are pure.

**Files:**
- Create: `tools/music/Sources/TUI/PlaylistBrowserModel.swift`
- Test: `tools/music/Tests/MusicTests/PlaylistBrowserModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `tools/music/Tests/MusicTests/PlaylistBrowserModelTests.swift`:

```swift
import XCTest
@testable import music

final class PlaylistBrowserModelTests: XCTestCase {
    // badge derivation
    func testRadioBadgeFromNamePrefix() {
        XCTAssertEqual(playlistBadge(name: "__radio__Tom Misch", isSmart: false, specialKind: "none"), .radio)
    }
    func testRecentBadgeFromKnownName() {
        XCTAssertEqual(playlistBadge(name: "Recently Played", isSmart: true, specialKind: "Music"), .recent)
        XCTAssertEqual(playlistBadge(name: "Top 25 Most Played", isSmart: true, specialKind: "Music"), .recent)
    }
    func testSmartBadge() {
        XCTAssertEqual(playlistBadge(name: "Deep House Finds", isSmart: true, specialKind: "none"), .smart)
    }
    func testNoneBadgeForPlainUserPlaylist() {
        XCTAssertEqual(playlistBadge(name: "Bluecoats 2024", isSmart: false, specialKind: "none"), .none)
    }
    func testRadioWinsOverSmart() {
        XCTAssertEqual(playlistBadge(name: "__radio__BORN FREE", isSmart: true, specialKind: "none"), .radio)
    }

    // duration formatting
    func testFormatDurationHoursAndMinutes() {
        XCTAssertEqual(formatPlaylistDuration(15132), "4h 12m")   // 4*3600 + 12*60 = 15120..15179
    }
    func testFormatDurationMinutesOnly() {
        XCTAssertEqual(formatPlaylistDuration(360), "6m")
    }
    func testFormatDurationZero() {
        XCTAssertEqual(formatPlaylistDuration(0), "0m")
    }
    func testFormatDurationRoundsDownToMinute() {
        XCTAssertEqual(formatPlaylistDuration(59), "0m")
    }

    // zone layout
    func testThreeZonesWhenWide() {
        let z = playlistZones(width: 188)
        XCTAssertEqual(z.mode, .three)
        XCTAssertGreaterThanOrEqual(z.railWidth, 30)
        XCTAssertNotNil(z.rightX)
        XCTAssertGreaterThan(z.heroX, z.railX + z.railWidth)
        XCTAssertGreaterThan(z.rightX!, z.heroX + z.heroWidth)
    }
    func testTwoZonesMidWidth() {
        let z = playlistZones(width: 120)
        XCTAssertEqual(z.mode, .two)
        XCTAssertNil(z.rightX)
    }
    func testOneZoneNarrow() {
        let z = playlistZones(width: 80)
        XCTAssertEqual(z.mode, .one)
        XCTAssertNil(z.rightX)
    }

    // enrichment batch selection
    func testEnrichmentPrioritizesVisibleUnloaded() {
        let batch = nextEnrichmentBatch(total: 20, loaded: [], visible: 10..<15, batchSize: 3)
        XCTAssertEqual(batch, [10, 11, 12]) // visible first, in order
    }
    func testEnrichmentSkipsLoaded() {
        let batch = nextEnrichmentBatch(total: 20, loaded: [10, 11], visible: 10..<15, batchSize: 3)
        XCTAssertEqual(batch, [12, 13, 14])
    }
    func testEnrichmentFallsBackToNonVisibleWhenVisibleDone() {
        let batch = nextEnrichmentBatch(total: 5, loaded: [2, 3, 4], visible: 2..<5, batchSize: 3)
        XCTAssertEqual(batch, [0, 1]) // visible all loaded -> earliest unloaded
    }
    func testEnrichmentEmptyWhenAllLoaded() {
        XCTAssertEqual(nextEnrichmentBatch(total: 3, loaded: [0, 1, 2], visible: 0..<3, batchSize: 5), [])
    }

    // gradient determinism
    func testGradientDeterministicAndSized() {
        let a = gradientBlock(name: "House Classics", width: 12, height: 5)
        let b = gradientBlock(name: "House Classics", width: 12, height: 5)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 5)
    }
    func testGradientDiffersByName() {
        let a = gradientBlock(name: "House Classics", width: 12, height: 5)
        let c = gradientBlock(name: "Jazz Nights", width: 12, height: 5)
        XCTAssertNotEqual(a, c)
    }

    // rail name truncation
    func testRailNameTruncatesWithEllipsis() {
        let r = railName("A Very Long Playlist Name That Overflows", nameWidth: 10)
        XCTAssertEqual(r.count, 10)
        XCTAssertTrue(r.hasSuffix("\u{2026}"))
    }
    func testRailNameShortUnchanged() {
        XCTAssertEqual(railName("Short", nameWidth: 10), "Short")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd tools/music && swift test --filter PlaylistBrowserModelTests`
Expected: FAIL — `playlistBadge`, `formatPlaylistDuration`, etc. not defined (compile error).

- [ ] **Step 3: Implement the model**

Create `tools/music/Sources/TUI/PlaylistBrowserModel.swift`:

```swift
import Foundation

// MARK: - Metadata

/// Per-playlist metadata. Optional fields are `nil` until enrichment loads
/// them; the UI renders a reserved placeholder so values land without shifting
/// layout.
struct PlaylistMeta {
    let name: String
    var trackCount: Int?
    var durationSec: Int?
    var isSmart: Bool?
    var specialKind: String?
    var loaded: Bool = false
}

enum PlaylistBadge: Equatable {
    case radio, smart, recent, none
}

private let recentPlaylistNames: Set<String> = ["Recently Played", "Top 25 Most Played"]

/// Pure badge derivation. radio > recent > smart > none.
func playlistBadge(name: String, isSmart: Bool, specialKind: String) -> PlaylistBadge {
    if name.hasPrefix("__radio__") { return .radio }
    if recentPlaylistNames.contains(name) { return .recent }
    if isSmart { return .smart }
    return .none
}

/// Format a duration in seconds as "Hh Mm" (or "Mm" under an hour).
func formatPlaylistDuration(_ seconds: Int) -> String {
    let totalMin = max(0, seconds) / 60
    let h = totalMin / 60
    let m = totalMin % 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

// MARK: - Zone geometry

enum PlaylistZoneMode { case one, two, three }

struct PlaylistZones {
    let mode: PlaylistZoneMode
    let railX: Int
    let railWidth: Int
    let heroX: Int
    let heroWidth: Int
    let rightX: Int?      // nil unless mode == .three
    let rightWidth: Int
}

/// Compute zone geometry from terminal width. Pure.
/// >=138: three zones; 96..137: rail+hero; <96: rail + compact hero.
func playlistZones(width: Int) -> PlaylistZones {
    let railX = 3
    let gutter = 3
    if width >= 138 {
        let railWidth = 34
        let heroX = railX + railWidth + gutter
        let heroWidth = min(54, (width - heroX - gutter - railX) / 2 + 6)
        let rightX = heroX + heroWidth + gutter
        let rightWidth = min(52, width - rightX - 2)
        return PlaylistZones(mode: .three, railX: railX, railWidth: railWidth,
                             heroX: heroX, heroWidth: heroWidth,
                             rightX: rightX, rightWidth: max(0, rightWidth))
    } else if width >= 96 {
        let railWidth = 34
        let heroX = railX + railWidth + gutter
        let heroWidth = max(0, width - heroX - 2)
        return PlaylistZones(mode: .two, railX: railX, railWidth: railWidth,
                             heroX: heroX, heroWidth: heroWidth,
                             rightX: nil, rightWidth: 0)
    } else {
        let railWidth = min(30, max(18, width / 2))
        let heroX = railX + railWidth + gutter
        let heroWidth = max(0, width - heroX - 2)
        return PlaylistZones(mode: .one, railX: railX, railWidth: railWidth,
                             heroX: heroX, heroWidth: heroWidth,
                             rightX: nil, rightWidth: 0)
    }
}

// MARK: - Enrichment queue

/// Choose the next batch of unloaded playlist indices to enrich, visible rows
/// first (in order), then the earliest remaining unloaded indices. Pure.
func nextEnrichmentBatch(total: Int, loaded: Set<Int>, visible: Range<Int>, batchSize: Int) -> [Int] {
    var picks: [Int] = []
    for i in visible where i >= 0 && i < total && !loaded.contains(i) {
        picks.append(i)
        if picks.count == batchSize { return picks }
    }
    var i = 0
    while i < total && picks.count < batchSize {
        if !loaded.contains(i) && !visible.contains(i) {
            picks.append(i)
        }
        i += 1
    }
    return picks
}

// MARK: - Gradient block (deterministic identity, not real artwork)

private let gradientGlyphs = "\u{2588}\u{2593}\u{2592}\u{2591}"  // █▓▒░

/// Build a deterministic block of `height` strings, each `width` glyphs,
/// seeded by the playlist name. No color codes here — caller wraps with color.
func gradientBlock(name: String, width: Int, height: Int) -> [String] {
    guard width > 0, height > 0 else { return [] }
    var seed = 5381
    for b in name.unicodeScalars { seed = ((seed << 5) &+ seed) &+ Int(b.value) }
    let glyphs = Array(gradientGlyphs)
    var rows: [String] = []
    for r in 0..<height {
        var line = ""
        for c in 0..<width {
            let idx = abs((seed &+ r &* 31 &+ c &* 7)) % glyphs.count
            line.append(glyphs[idx])
        }
        rows.append(line)
    }
    return rows
}

// MARK: - Rail name truncation

/// Truncate a playlist name to exactly fit `nameWidth` columns, ellipsis if cut.
func railName(_ name: String, nameWidth: Int) -> String {
    guard nameWidth > 0 else { return "" }
    if name.count <= nameWidth { return name }
    if nameWidth == 1 { return "\u{2026}" }
    return String(name.prefix(nameWidth - 1)) + "\u{2026}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd tools/music && swift test --filter PlaylistBrowserModelTests`
Expected: PASS (all ~17 tests).

- [ ] **Step 5: Run the full suite (no regressions)**

Run: `cd tools/music && swift test`
Expected: previous 34 + new tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add tools/music/Sources/TUI/PlaylistBrowserModel.swift tools/music/Tests/MusicTests/PlaylistBrowserModelTests.swift
git commit -m "feat(tui): pure playlist-browser model (zones, badges, duration, enrichment queue, gradient)"
```

---

## Task 3: Data hooks in PlaylistCommands

Add a batched metadata fetch and a light preview fetch, and widen the playlist enumeration to capture nothing extra yet (names only stay at launch — metadata comes via `onMeta`). These closures are injected into `runPlaylistBrowser` (signature changes in Task 4; this task defines the closures and is committed together with Task 4's signature change, so build both before committing — see Task 4 Step for the combined build/commit).

**Files:**
- Modify: `tools/music/Sources/Commands/PlaylistCommands.swift` (the `PlaylistBrowse.run()` body, around lines 33–94)

- [ ] **Step 1: Add a raw-metadata struct and the batched fetch closure**

In `PlaylistBrowse.run()`, after `names` is built and before `runPlaylistBrowser` is called, add:

```swift
        // Batched metadata fetch for a set of playlist indices.
        // Returns: index -> (count, durationSec, isSmart, specialKind)
        let onMeta: ([Int]) -> [Int: (Int, Int, Bool, String)] = { indices in
            guard !indices.isEmpty else { return [:] }
            // Build an AppleScript that returns one line per requested index:
            //   <idx>|<count>|<duration>|<smart>|<specialKind>
            var clauses = ""
            for idx in indices where idx >= 0 && idx < names.count {
                let esc = escapeAppleScriptString(names[idx])
                clauses += """
                set p to playlist "\(esc)"
                set output to output & "\(idx)|" & (count of tracks of p) & "|" & (duration of p) & "|" & (smart of p) & "|" & (special kind of p as text) & linefeed

                """
            }
            guard let result = try? syncRun({
                try await backend.runMusic("""
                    set output to ""
                    \(clauses)
                    return output
                """)
            }) else { return [:] }
            var out: [Int: (Int, Int, Bool, String)] = [:]
            for line in result.split(separator: "\n") {
                let f = line.split(separator: "|", maxSplits: 4).map(String.init)
                guard f.count == 5, let idx = Int(f[0]) else { continue }
                let count = Int(f[1]) ?? 0
                let dur = Int(Double(f[2]) ?? 0)
                let smart = f[3].trimmingCharacters(in: .whitespaces) == "true"
                out[idx] = (count, dur, smart, f[4].trimmingCharacters(in: .whitespaces))
            }
            return out
        }
```

NOTE: `escapeAppleScriptString` is the shared helper (Backends/AppleScriptEscaping.swift). Using a per-playlist `playlist "name"` lookup avoids index drift if Music reorders.

- [ ] **Step 2: Add the light 8-track preview fetch**

Add below `onMeta`:

```swift
        // Light preview: first 8 "Title — Artist" lines for one playlist.
        var previewCacheLight: [Int: [String]] = [:]
        let onPreview: (Int) -> [String]? = { idx in
            if let c = previewCacheLight[idx] { return c }
            guard idx >= 0, idx < names.count else { return nil }
            let esc = escapeAppleScriptString(names[idx])
            guard let res = try? syncRun({
                try await backend.runMusic("""
                    set output to ""
                    set i to 1
                    repeat with t in (every track of playlist "\(esc)")
                        if i > 8 then exit repeat
                        if output is not "" then set output to output & linefeed
                        set output to output & name of t & " \u{2014} " & artist of t
                        set i to i + 1
                    end repeat
                    return output
                """)
            }) else { return nil }
            let lines = res.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n").map(String.init)
            previewCacheLight[idx] = lines
            return lines
        }
```

- [ ] **Step 3: (No build yet — signature consumed in Task 4.)** Proceed to Task 4; build and commit Tasks 3+4 together.

---

## Task 4: Rewrite `runPlaylistBrowser` — 3-zone shell (names only)

Replace the 2-pane render with the 3-zone shell: rail with reserved meta column (placeholder dots, no enrichment yet), hero with title only, empty right panel. No enrichment loop yet — prove the layout first.

**Files:**
- Modify: `tools/music/Sources/TUI/ListPicker.swift` (`runPlaylistBrowser`, lines 42–288)
- Modify: `tools/music/Sources/Commands/PlaylistCommands.swift` (the `runPlaylistBrowser(...)` call, line ~90)

- [ ] **Step 1: Change the signature and build the model state**

Replace the signature and the head of `runPlaylistBrowser` (lines 42–94) with:

```swift
func runPlaylistBrowser(
    playlists: [String],
    onMeta: @escaping ([Int]) -> [Int: (Int, Int, Bool, String)],
    onPreview: @escaping (Int) -> [String]?,
    onTracks: @escaping (Int) -> PlaylistPreview?,
    savedState: BrowserState? = nil
) -> BrowserResult {
    let terminal = TerminalState.shared
    terminal.enterRawMode()
    defer { terminal.exitRawMode() }
    print(ANSICode.cursorHome + ANSICode.clearScreen, terminator: "")

    var focus: BrowserFocus = savedState?.focus ?? .playlists
    var plCursor = savedState?.plCursor ?? 0
    var plScroll = savedState?.plScroll ?? 0
    var trCursor = savedState?.trCursor ?? 0
    var trScroll = savedState?.trScroll ?? 0

    var meta: [PlaylistMeta] = playlists.map { PlaylistMeta(name: $0) }
    var loaded: Set<Int> = []
    var fullCache: [Int: PlaylistPreview] = [:]
    var lastLoadedPl = -1

    func currentState() -> BrowserState {
        BrowserState(plCursor: plCursor, plScroll: plScroll,
                     trCursor: trCursor, trScroll: trScroll, focus: focus)
    }

    func loadFull() {
        guard plCursor != lastLoadedPl else { return }
        lastLoadedPl = plCursor
        if fullCache[plCursor] == nil { fullCache[plCursor] = onTracks(plCursor) }
        if savedState == nil || plCursor != (savedState?.plCursor ?? -1) {
            trCursor = 0; trScroll = 0
        }
    }

    func makeContext(trackIndex: Int) -> PlaybackContext {
        let preview = fullCache[plCursor]
        return PlaybackContext(playlistName: playlists[plCursor],
                               tracks: preview?.tracks ?? [], startIndex: trackIndex)
    }
```

- [ ] **Step 2: Write the rail renderer with reserved meta column**

Add inside `runPlaylistBrowser`, before the main `render()`:

```swift
    let metaCol = 6  // reserved right column in the rail for count/badge

    func badgeText(_ m: PlaylistMeta) -> (String, String)? {
        // returns (text, colorCode) or nil to show count
        let b = playlistBadge(name: m.name, isSmart: m.isSmart ?? false,
                              specialKind: m.specialKind ?? "none")
        switch b {
        case .radio: return ("RADIO", ANSICode.amber)
        case .smart: return ("SMART", ANSICode.amber)
        case .recent: return ("RECENT", ANSICode.amber)
        case .none: return nil
        }
    }

    func renderRail(_ z: PlaylistZones, into out: inout String, listY: Int, maxVisible: Int) {
        if plCursor < plScroll { plScroll = plCursor }
        if plCursor >= plScroll + maxVisible { plScroll = plCursor - maxVisible + 1 }
        let end = min(meta.count, plScroll + maxVisible)
        let nameWidth = z.railWidth - 2 - metaCol - 1
        for i in plScroll..<end {
            let row = listY + (i - plScroll)
            out += ANSICode.moveTo(row: row, col: z.railX)
            let m = meta[i]
            let display = m.name.hasPrefix("__radio__")
                ? String(m.name.dropFirst("__radio__".count))
                : m.name
            let nm = railName(display, nameWidth: max(1, nameWidth))

            // right meta cell (fixed width = metaCol), reserved always
            let metaCell: String
            if !m.loaded {
                metaCell = "\(ANSICode.dim)\(String(repeating: " ", count: metaCol - 1))\u{00B7}\(ANSICode.reset)"
            } else if let (text, color) = badgeText(m) {
                let padded = String(repeating: " ", count: max(0, metaCol - text.count)) + text
                metaCell = "\(color)\(padded)\(ANSICode.reset)"
            } else {
                let c = "\(m.trackCount ?? 0)"
                let padded = String(repeating: " ", count: max(0, metaCol - c.count)) + c
                metaCell = "\(ANSICode.dim)\(padded)\(ANSICode.reset)"
            }

            let padName = nm + String(repeating: " ", count: max(0, nameWidth - nm.count))
            if i == plCursor {
                let mark = (focus == .playlists) ? ANSICode.cyan : ANSICode.dim
                out += "\(mark)\u{258C}\(ANSICode.reset) \(ANSICode.brightWhite)\(padName)\(ANSICode.reset) \(metaCell)"
            } else {
                out += "  \(padName) \(metaCell)"
            }
        }
    }
```

- [ ] **Step 3: Write the hero renderer (title only for now)**

```swift
    func renderHero(_ z: PlaylistZones, into out: inout String) {
        let y = ScreenFrame.current().bodyY
        let m = meta[plCursor]
        out += ANSICode.moveTo(row: y, col: z.heroX)
        out += "\(ANSICode.bold)\(ANSICode.brightWhite)\(truncText(m.name, to: z.heroWidth))\(ANSICode.reset)"
    }
```

- [ ] **Step 4: Write the main render() that composes zones**

```swift
    func render() {
        let frame = ScreenFrame.current()
        let z = playlistZones(width: frame.width)
        let listY = frame.bodyY + 2
        let maxVisible = max(1, frame.statusY - listY - 1)

        let pending = loaded.count < meta.count
        let statusText = pending
            ? "Loading metadata\u{2026} \(loaded.count)/\(meta.count)"
            : "\(meta.count) playlists"
        let footerText = "\(ANSICode.bold)\u{2191}\u{2193}\(ANSICode.reset) Browse   \(ANSICode.bold)Enter\(ANSICode.reset) Open   \(ANSICode.bold)p\(ANSICode.reset) Play   \(ANSICode.bold)s\(ANSICode.reset) Shuffle   \(ANSICode.bold)/\(ANSICode.reset) Filter   \(ANSICode.bold)b\(ANSICode.reset) Now   \(ANSICode.bold)q\(ANSICode.reset) Quit"

        var out = renderShell(title: "Playlists", status: statusText, footer: footerText)
        out += clearBody(frame)
        renderRail(z, into: &out, listY: listY, maxVisible: maxVisible)
        renderHero(z, into: &out)
        // right panel added in Task 7
        print(out, terminator: "")
        fflush(stdout)
    }
```

- [ ] **Step 5: Keep the existing input loop, but with names-only navigation**

Replace the `while true` loop body's navigation so it no longer calls the removed `loadPreview`. Use `loadFull()` only on Enter/Tab. The key handlers for `.up/.down/.enter/.char("p")/.char("s")/.char("b")/.char("q")/.left/.escape` stay structurally the same as the current file (lines 220–286) EXCEPT: replace every `loadPreview()` call with `loadFull()`, and remove the `if previewCache[plCursor] != nil { loadPreview() }` lines on up/down (no eager full load while browsing). Track-focus rendering (the right pane track list) is deferred to Task 7; for now `.enter` on a playlist calls `loadFull()` then `focus = .tracks` but the right panel won't show until Task 7 — acceptable intermediate state.

Final `render()` call at the end of the loop stays.

- [ ] **Step 6: Update the caller**

In `PlaylistCommands.swift`, change the `runPlaylistBrowser(...)` call (line ~90) to pass the new closures:

```swift
            let result = runPlaylistBrowser(
                playlists: names,
                onMeta: onMeta,
                onPreview: onPreview,
                onTracks: onTracks,
                savedState: browserState
            )
```

The existing `onTracks` closure (lines 57–85) stays as-is (full 200-track fetch).

- [ ] **Step 7: Build**

Run: `cd tools/music && swift build`
Expected: `Build complete!`. Fix any signature mismatches.

- [ ] **Step 8: Run full test suite**

Run: `cd tools/music && swift test`
Expected: 0 failures (model tests + prior 34).

- [ ] **Step 9: Commit (Tasks 3 + 4 together)**

```bash
git add tools/music/Sources/TUI/ListPicker.swift tools/music/Sources/Commands/PlaylistCommands.swift
git commit -m "feat(tui): 3-zone playlist browser shell + metadata/preview data hooks"
```

- [ ] **Step 10: MANUAL VERIFICATION (user)**

Rebuild and run: `scripts/install.sh && music playlist`. Confirm: rail shows names with a reserved dim `·` in the right column; selected row has a bright bar; hero shows the selected playlist title; no garbled overlap; scrolling is clean. (Counts/badges stay as `·` — enrichment is Task 5.)

---

## Task 5: Tick-driven enrichment + status line

Wire the enrichment loop so metadata fills in progressively, visible-first, without layout shift.

**Files:**
- Modify: `tools/music/Sources/TUI/ListPicker.swift` (`runPlaylistBrowser` loop)

- [ ] **Step 1: Add an enrichment step function**

Inside `runPlaylistBrowser`, before the loop:

```swift
    let enrichBatch = 5

    func enrichTick() {
        let frame = ScreenFrame.current()
        let listY = frame.bodyY + 2
        let maxVisible = max(1, frame.statusY - listY - 1)
        let visible = plScroll..<min(meta.count, plScroll + maxVisible)
        let batch = nextEnrichmentBatch(total: meta.count, loaded: loaded,
                                        visible: visible, batchSize: enrichBatch)
        guard !batch.isEmpty else { return }
        let fetched = onMeta(batch)
        for idx in batch {
            if let (count, dur, smart, kind) = fetched[idx] {
                meta[idx].trackCount = count
                meta[idx].durationSec = dur
                meta[idx].isSmart = smart
                meta[idx].specialKind = kind
            }
            meta[idx].loaded = true   // mark loaded even on fetch miss to avoid loops
            loaded.insert(idx)
        }
    }
```

- [ ] **Step 2: Change the loop timeout to tick when work pending**

Replace `let key = KeyPress.read(timeout: 60.0)` with:

```swift
        let pending = loaded.count < meta.count
        let key = KeyPress.read(timeout: pending ? 0.15 : 60.0)
        if key == nil {
            if pending { enrichTick(); render() }
            continue
        }
```

(The existing `guard let key = key else { continue }` line is now replaced by the block above — remove the old guard.)

- [ ] **Step 3: Build + test**

Run: `cd tools/music && swift build && swift test`
Expected: build clean, 0 test failures.

- [ ] **Step 4: Commit**

```bash
git add tools/music/Sources/TUI/ListPicker.swift
git commit -m "feat(tui): tick-driven progressive metadata enrichment + status line"
```

- [ ] **Step 5: MANUAL VERIFICATION (user)**

`scripts/install.sh && music playlist`. Confirm: rail opens instantly; counts/badges fill in within a second or two, visible rows first; status line shows `Loading metadata… N/55` then disappears; names do NOT shift when values land; scrolling to an unloaded region fills it next.

---

## Task 6: Hero card (gradient, subtitle, badges, actions)

**Files:**
- Modify: `tools/music/Sources/TUI/ListPicker.swift` (`renderHero`)

- [ ] **Step 1: Expand `renderHero`**

Replace `renderHero` with:

```swift
    func renderHero(_ z: PlaylistZones, into out: inout String) {
        let frame = ScreenFrame.current()
        var y = frame.bodyY
        let m = meta[plCursor]

        // Title
        let title = m.name.hasPrefix("__radio__") ? String(m.name.dropFirst(9)) : m.name
        out += ANSICode.moveTo(row: y, col: z.heroX)
        out += "\(ANSICode.bold)\(ANSICode.brightWhite)\(truncText(title, to: z.heroWidth))\(ANSICode.reset)"
        y += 1

        // Subtitle (truthful: only when loaded)
        out += ANSICode.moveTo(row: y, col: z.heroX)
        if m.loaded, let c = m.trackCount {
            let dur = m.durationSec.map { " \u{00B7} " + formatPlaylistDuration($0) } ?? ""
            out += "\(ANSICode.dim)\(c) tracks\(dur)\(ANSICode.reset)"
        }
        y += 2

        // Gradient identity block
        let gw = min(16, z.heroWidth)
        let block = gradientBlock(name: m.name, width: gw, height: 6)
        // deterministic hue from name
        var seed = 0; for b in m.name.unicodeScalars { seed = (seed &* 31 &+ Int(b.value)) & 0xffffff }
        let r = 80 + (seed & 0x7f), g = 80 + ((seed >> 8) & 0x7f), bl = 80 + ((seed >> 16) & 0x7f)
        let color = "\u{1B}[38;2;\(r);\(g);\(bl)m"
        for line in block {
            out += ANSICode.moveTo(row: y, col: z.heroX)
            out += "\(color)\(line)\(ANSICode.reset)"
            y += 1
        }
        y += 1

        // Badge chip
        if let (text, c) = badgeText(m) {
            out += ANSICode.moveTo(row: y, col: z.heroX)
            out += "\(c)\(text)\(ANSICode.reset)"
            y += 2
        } else {
            y += 1
        }

        // Actions
        out += ANSICode.moveTo(row: y, col: z.heroX)
        out += "\(ANSICode.lime)[Enter]\(ANSICode.reset) Browse   \(ANSICode.lime)[P]\(ANSICode.reset) Play   \(ANSICode.lime)[S]\(ANSICode.reset) Shuffle   \(ANSICode.lime)[/]\(ANSICode.reset) Filter"
    }
```

- [ ] **Step 2: Build + test**

Run: `cd tools/music && swift build && swift test`
Expected: clean, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add tools/music/Sources/TUI/ListPicker.swift
git commit -m "feat(tui): hero card with gradient block, subtitle, badge, actions"
```

- [ ] **Step 4: MANUAL VERIFICATION (user)**

`scripts/install.sh && music playlist`. Confirm: hero shows a dominant title, a `N tracks · Hh Mm` subtitle once loaded (blank, never fake, before), a colored gradient block whose color/pattern is stable per playlist and differs between playlists, a badge chip for radio/smart/recent, and a lime action row. Moving the cursor updates all of it.

---

## Task 7: Right panel — Preview (light fetch on cursor-settle)

**Files:**
- Modify: `tools/music/Sources/TUI/ListPicker.swift`

- [ ] **Step 1: Add settle tracking + preview cache state**

Add near the other state vars:

```swift
    var previewLines: [Int: [String]] = [:]
    var settleTicks = 0          // idle ticks since last cursor move
    var lastPreviewLoaded = -1
```

In every navigation handler that changes `plCursor` (up/down), add `settleTicks = 0` so movement resets the debounce.

- [ ] **Step 2: Add a preview renderer**

```swift
    func renderPreview(_ z: PlaylistZones, into out: inout String) {
        guard z.mode == .three, let rx = z.rightX else { return }
        let frame = ScreenFrame.current()
        var y = frame.bodyY
        out += ANSICode.moveTo(row: y, col: rx)
        out += "\(ANSICode.cyan)Preview\(ANSICode.reset)"
        y += 1
        out += ANSICode.moveTo(row: y, col: rx)
        out += "\(ANSICode.dim)\(String(repeating: "\u{2500}", count: min(z.rightWidth, 18)))\(ANSICode.reset)"
        y += 1
        if let lines = previewLines[plCursor] {
            for (i, line) in lines.prefix(8).enumerated() {
                out += ANSICode.moveTo(row: y, col: rx)
                let idx = String(format: "%02d", i + 1)
                out += "\(ANSICode.dim)\(idx)\(ANSICode.reset)  \(truncText(line, to: z.rightWidth - 4))"
                y += 1
            }
        } else {
            out += ANSICode.moveTo(row: y, col: rx)
            out += "\(ANSICode.dim)Loading preview\u{2026}\(ANSICode.reset)"
        }
    }
```

Add `renderPreview(z, into: &out)` in `render()` after `renderHero(...)`.

- [ ] **Step 3: Trigger the light preview on settle**

In the `key == nil` idle branch (Task 5 Step 2), after the `enrichTick()` block, add settle-driven preview loading:

```swift
        if key == nil {
            if pending { enrichTick() }
            settleTicks += 1
            if settleTicks >= 1 && lastPreviewLoaded != plCursor && previewLines[plCursor] == nil {
                previewLines[plCursor] = onPreview(plCursor) ?? []
                lastPreviewLoaded = plCursor
            }
            render()
            continue
        }
```

(Replace the simpler `key == nil` block from Task 5 with this one.)

- [ ] **Step 4: Build + test**

Run: `cd tools/music && swift build && swift test`
Expected: clean, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add tools/music/Sources/TUI/ListPicker.swift
git commit -m "feat(tui): right-panel preview (light 8-track fetch on cursor-settle)"
```

- [ ] **Step 6: MANUAL VERIFICATION (user)**

`scripts/install.sh && music playlist`. Confirm (in a ≥138-col terminal): a `Preview` panel appears on the right; settling on a playlist for a beat loads its first ~8 tracks; fast scrolling shows `Loading preview…` and does not lag the rail; no old `Enter to browse tracks` text appears. In a narrower terminal the panel is absent and nothing breaks.

---

## Task 8: Filter (`/`)

**Files:**
- Modify: `tools/music/Sources/TUI/ListPicker.swift`

- [ ] **Step 1: Add filter state + a filtered-index helper**

Add state:

```swift
    var filterText = ""
    var filtering = false
```

Add a computed visible-index list. Since `meta`/`plCursor` index into the full arrays, keep filtering as a display filter: build `visibleIndices` each render.

```swift
    func visibleIndices() -> [Int] {
        guard !filterText.isEmpty else { return Array(0..<meta.count) }
        let q = filterText.lowercased()
        return (0..<meta.count).filter { meta[$0].name.lowercased().contains(q) }
    }
```

- [ ] **Step 2: Render against filtered indices**

Modify `renderRail` to iterate `visibleIndices()` rather than `0..<meta.count`, and map scroll/cursor to positions within that list. Implementation: compute `let vis = visibleIndices()`, clamp a *position* `pos` (cursor's position in `vis`), scroll within `vis`, and render `vis[pos]`. Maintain `plCursor` as the actual playlist index = `vis[pos]`. Add a filter line under the title when `filtering || !filterText.isEmpty`:

```swift
        if filtering || !filterText.isEmpty {
            out += ANSICode.moveTo(row: frame.bodyY, col: z.railX)
            out += "\(ANSICode.cyan)/\(ANSICode.reset) \(ANSICode.brightWhite)\(filterText)\(ANSICode.reset)\(filtering ? "\u{2588}" : "")"
        }
```

(Render the rail starting one row lower when the filter line is shown.)

- [ ] **Step 3: Handle filter input**

In the key switch, add:

```swift
        case .char("/"):
            filtering = true
        case .char(let c) where filtering && c != "/":
            filterText.append(c)
        case .enter where filtering:
            filtering = false
        case .escape where filtering:
            filtering = false; filterText = ""
```

Add backspace handling: in `KeyPress` parsing, byte `127`/`8` → a `.char("\u{8}")`; in the switch, when `filtering` and that char arrives, drop the last `filterText` character. (If `KeyPress` has no backspace case, add one in `Terminal.swift` `parseKey`: `case 127, 8: return .char("\u{8}")`.)

Guard the existing letter shortcuts (`p`, `s`, `b`, `q`) so they only fire when `!filtering`.

- [ ] **Step 4: Build + test**

Run: `cd tools/music && swift build && swift test`
Expected: clean, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add tools/music/Sources/TUI/ListPicker.swift tools/music/Sources/TUI/Terminal.swift
git commit -m "feat(tui): client-side playlist filter (/)"
```

- [ ] **Step 6: MANUAL VERIFICATION (user)**

`scripts/install.sh && music playlist`. Confirm: `/` opens a filter line; typing narrows the rail instantly; Backspace edits; Enter keeps the filter and returns to navigation; Esc clears it; `p`/`s`/`q` are not swallowed while typing.

---

## Task 9: Track-focus list in the right panel + final polish

Restore full track browsing (Enter → scrollable track list in the right zone) using the existing `onTracks` full fetch, and do a final color/footer pass.

**Files:**
- Modify: `tools/music/Sources/TUI/ListPicker.swift`

- [ ] **Step 1: When `focus == .tracks`, render the full track list in the right zone**

In `render()`, when `focus == .tracks` and a full preview is cached (`fullCache[plCursor]`), render its tracks (scrollable, `trCursor`/`trScroll`) in the right zone instead of the light preview — reuse the track-row format from the old code (index + `truncText(track, to: rightWidth - 6)`, cyan ▶ on the selected track). When `focus == .playlists`, render the light preview (Task 7).

- [ ] **Step 2: Wire Enter/Tab to load full + focus tracks, Enter-on-track to play**

Confirm the loop: `.enter` when `focus == .playlists` → `loadFull(); focus = .tracks; trCursor = 0`. `.enter` when `focus == .tracks` → `return .playTrack(...)` (as in the original code, lines 246–256). `.left/.escape` from tracks → `focus = .playlists`.

- [ ] **Step 3: Final color/footer pass**

Verify the five-role palette is used consistently (cyan headers, brightWhite selected title/values, lime active+actions, dim metadata, amber badges) and the footer matches Task 4. Remove any leftover green-on-everything.

- [ ] **Step 4: Build + full test**

Run: `cd tools/music && swift build && swift test`
Expected: clean, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add tools/music/Sources/TUI/ListPicker.swift
git commit -m "feat(tui): track-focus list in right zone + final color/footer polish"
```

- [ ] **Step 6: MANUAL VERIFICATION (user) — full acceptance**

`scripts/install.sh && music playlist`. Confirm end-to-end: instant first paint; progressive metadata fill, no layout shift; hero updates on navigation; preview loads on settle; Enter opens a scrollable track list; selecting a track plays it and opens now-playing; `b`/back returns and restores browser state; filter works; five-role color (not all-green); no ghosting/flicker. Report anything that feels off for tuning (batch size, debounce, gradient).

---

## Self-Review

**Spec coverage:**
- 3-zone responsive layout → Task 2 (`playlistZones`) + Task 4. ✓
- Truthful data / no fake timestamps or mood → only count/duration/badges rendered; never fabricated. ✓
- Instant shell + progressive enrichment + status line → Tasks 4, 5. ✓
- Stable rail rows (reserved meta column) → Task 4 Step 2. ✓
- Hero card (gradient, subtitle, badges, actions) → Task 6. ✓
- Right-panel preview (light 8-track) → Task 7. ✓
- Five-role color system → Task 1 + Task 9 Step 3. ✓
- Filter → Task 8. ✓
- Keep `clearBody` flicker fix → Task 4 Step 4 (render uses `clearBody`). ✓
- Track browsing / play flow preserved → Task 9. ✓
- Deferred (artwork, Now-Playing/Recent modes, Tab cycling, genre) → not in plan, by design. ✓

**Placeholder scan:** No "TBD"/"handle edge cases" left. Task 4 Step 5 and Task 9 Step 1 reference the *existing* code regions by line and describe the exact transformation (replace `loadPreview`→`loadFull`; reuse track-row format) rather than inventing — acceptable since the engineer has the file open; the concrete formats are given.

**Type consistency:** `onMeta` returns `[Int: (Int, Int, Bool, String)]` in Task 3 and is consumed identically in Tasks 4–5. `PlaylistMeta` fields (`trackCount`, `durationSec`, `isSmart`, `specialKind`, `loaded`) are set in Task 5 exactly as declared in Task 2. `playlistZones`, `nextEnrichmentBatch`, `gradientBlock`, `railName`, `playlistBadge`, `formatPlaylistDuration` signatures match between Task 2 definitions and later call sites. `ANSICode.brightWhite/lime/amber` defined in Task 1, used from Task 4 on.

**Known soft spots flagged for the implementer:** Task 8 Step 2 (filter scroll/cursor mapping against a filtered index list) is the most intricate change — the cursor must track a *position within `visibleIndices()`* while `plCursor` stays the real index; build incrementally and test by eye. Backspace key plumbing (Task 8 Step 3) may require a small `parseKey` addition.
