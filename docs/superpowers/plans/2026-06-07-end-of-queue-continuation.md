# End-of-Queue Continuation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a playlist ends and Apple Music falls into library autoplay, detect the transition and show a card menu in Now Playing (Artist Radio / Playlist / Quiet) whose selection force-overrides autoplay.

**Architecture:** The poller gains queue-end *detection* (a pure guard over the prev/next context) and, on detection, captures an "ended-context" snapshot (playlist name, last track + artist, that track's album art) into the store. `NowPlayingScene` renders a card menu when `queueEnded` and force-plays the chosen action. A manual trigger key opens the same menu on demand (de-risks detection). `startRadioStation` is parameterized so Radio seeds from the *remembered* ended track, not the current (autoplay) track. (Similar is intentionally out of scope — Radio covers the "more like this" need.)

**Tech Stack:** Swift 5, AppleScript via `osascript`, REST catalog API, `chafa`/CoreGraphics art, XCTest.

**Reference spec:** `docs/superpowers/specs/2026-06-07-end-of-queue-continuation-design.md`
**Builds on:** v1.9.x shell (`98b1d30 … d856de2`).

**Working location:** repo root `/Users/anthonymaley/apple-music`; `swift` from `tools/music`; `git` from repo root. Commit per task, push after each. Before every commit run `git diff --cached --stat` and confirm only intended files are staged; never stage `docs/playlist-browser-ui.md`.

---

## File Structure

Modified:
- `Sources/TUI/Shell/PlaybackContext.swift` — `ContextQueue` gains `currentIndex`/`total`; `pollContextQueue` AppleScript emits total; `parseContextQueue` reads them. Add `isLibraryContextName(_:)` + pure `detectQueueEnd(...)`.
- `Sources/TUI/Shell/NowPlayingStore.swift` — `NowPlayingSnapshot` gains queue-end fields.
- `Sources/TUI/Shell/PlaybackPoller.swift` — track prior position/context; run detection; capture ended-context + art; publish.
- `Sources/TUI/Shell/NowPlayingScene.swift` — card menu render + R/S/P/Q handling + manual trigger key.
- `Sources/TUI/NowPlayingTUI.swift` — parameterize `startRadioStation`.

Tests:
- `Tests/MusicTests/PlaybackContextTests.swift` — extend (currentIndex/total parse).
- `Tests/MusicTests/QueueEndTests.swift` — new (detection guard + library-name + key→action).

---

## Task 1: ContextQueue carries currentIndex + total

**Files:**
- Modify: `tools/music/Sources/TUI/Shell/PlaybackContext.swift`
- Modify: `tools/music/Tests/MusicTests/PlaybackContextTests.swift`

Detection needs to know whether the just-ended track was the *last* in its playlist, so the queue must report `currentIndex` and `total`.

- [ ] **Step 1: Update the parse test**

Replace `testParsesWindowMarksCurrentByIndex` in `PlaybackContextTests.swift` with (note the new line-3 `total` field in the format):

```swift
    func testParsesWindowMarksCurrentByIndex() {
        // Format: "name\ncurrentIndex\ntotal\nwindowStart\nidx|title|artist..."
        let raw = "Friday Mix\n3\n42\n2\n2|Song B|Artist B\n3|Song C|Artist C\n4|Song C|Artist C"
        let q = parseContextQueue(raw)
        XCTAssertEqual(q.name, "Friday Mix")
        XCTAssertEqual(q.currentIndex, 3)
        XCTAssertEqual(q.total, 42)
        XCTAssertEqual(q.tracks.count, 3)
        XCTAssertEqual(q.tracks[1].index, 3)
        XCTAssertTrue(q.tracks[1].isCurrent)
        XCTAssertFalse(q.tracks[2].isCurrent)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/music && swift test --filter PlaybackContextTests`
Expected: FAIL — `ContextQueue` has no `currentIndex`/`total`; format mismatch.

- [ ] **Step 3: Update `ContextQueue`, `parseContextQueue`, and `pollContextQueue`**

In `PlaybackContext.swift`, change the struct:

```swift
struct ContextQueue {
    let name: String
    let currentIndex: Int
    let total: Int
    let tracks: [TrackListEntry]
}
```

Replace `parseContextQueue` (new line-3 `total`; window start moves to line 4):

```swift
func parseContextQueue(_ raw: String) -> ContextQueue {
    let lines = raw.components(separatedBy: "\n")
    guard lines.count >= 4 else { return ContextQueue(name: "", currentIndex: -1, total: 0, tracks: []) }
    let name = lines[0].trimmingCharacters(in: .whitespaces)
    let currentIndex = Int(lines[1].trimmingCharacters(in: .whitespaces)) ?? -1
    let total = Int(lines[2].trimmingCharacters(in: .whitespaces)) ?? 0
    var tracks: [TrackListEntry] = []
    for line in lines.dropFirst(4) where !line.isEmpty {
        let f = line.split(separator: "|", maxSplits: 2).map(String.init)
        guard f.count == 3, let idx = Int(f[0]) else { continue }
        tracks.append(TrackListEntry(index: idx, name: f[1], artist: f[2], isCurrent: idx == currentIndex))
    }
    return ContextQueue(name: name, currentIndex: currentIndex, total: total, tracks: tracks)
}
```

In `pollContextQueue`'s AppleScript, change the `set output to ...` header line to also emit `total` (insert it after `idx`):

```
                set output to cpName & linefeed & idx & linefeed & total & linefeed & startIdx
```

And the empty-return path (the `else { return ContextQueue(...) }` if present and any guard) must use the new initializer `ContextQueue(name: "", currentIndex: -1, total: 0, tracks: [])`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/music && swift test --filter PlaybackContextTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Build (the new initializer touches callers)**

Run: `cd tools/music && swift build`
Expected: Build succeeds. (The poller constructs/consumes `ContextQueue` via `pollContextQueue`; only `.name`/`.tracks` are read today, so it still compiles.)

- [ ] **Step 6: Commit**

```bash
git add tools/music/Sources/TUI/Shell/PlaybackContext.swift tools/music/Tests/MusicTests/PlaybackContextTests.swift
git diff --cached --stat
git commit -m "$(printf 'feat(shell): ContextQueue reports currentIndex + total\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Task 2: Snapshot queue-end fields

**Files:**
- Modify: `tools/music/Sources/TUI/Shell/NowPlayingStore.swift`

- [ ] **Step 1: Add fields (defaulted, so existing constructions compile)**

In `NowPlayingSnapshot`, add after `artLines`:

```swift
    var queueEnded: Bool = false           // show the continuation card menu
    var endedPlaylist: String = ""         // playlist that just ended
    var endedTrack: String = ""            // last context track title (seed for Radio/Similar)
    var endedArtist: String = ""           // last context track artist
    var endedArtLines: [String] = []       // last context track album art (captured at detection)
```

- [ ] **Step 2: Build**

Run: `cd tools/music && swift build`
Expected: Build succeeds (all new fields defaulted; existing `NowPlayingSnapshot(...)` calls in the poller still valid).

- [ ] **Step 3: Commit**

```bash
git add tools/music/Sources/TUI/Shell/NowPlayingStore.swift
git diff --cached --stat
git commit -m "$(printf 'feat(shell): snapshot fields for end-of-queue continuation\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Task 3: Pure detection guard + library-name helper

**Files:**
- Modify: `tools/music/Sources/TUI/Shell/PlaybackContext.swift`
- Create: `tools/music/Tests/MusicTests/QueueEndTests.swift`

The guard fires only on a real playlist's last track ending naturally and the context flipping to the library.

- [ ] **Step 1: Write the failing test**

```swift
// tools/music/Tests/MusicTests/QueueEndTests.swift
import XCTest
@testable import music

final class QueueEndTests: XCTestCase {
    func testLibraryNameDetection() {
        XCTAssertTrue(isLibraryContextName("Music"))
        XCTAssertTrue(isLibraryContextName("Library"))
        XCTAssertFalse(isLibraryContextName("Friday Mix"))
        XCTAssertFalse(isLibraryContextName(""))
    }
    func testFiresOnNaturalQueueEnd() {
        XCTAssertTrue(detectQueueEnd(
            prevWasRealPlaylist: true, prevAtLastTrack: true,
            prevNaturalEnd: true, nowIsLibraryAutoplay: true))
    }
    func testNoFireWhenPrevWasLibrary() {
        XCTAssertFalse(detectQueueEnd(
            prevWasRealPlaylist: false, prevAtLastTrack: true,
            prevNaturalEnd: true, nowIsLibraryAutoplay: true))
    }
    func testNoFireMidPlaylist() {
        XCTAssertFalse(detectQueueEnd(
            prevWasRealPlaylist: true, prevAtLastTrack: false,
            prevNaturalEnd: true, nowIsLibraryAutoplay: true))
    }
    func testNoFireOnManualLibraryJump() {
        // prev was last track but not a natural end (user skipped to library)
        XCTAssertFalse(detectQueueEnd(
            prevWasRealPlaylist: true, prevAtLastTrack: true,
            prevNaturalEnd: false, nowIsLibraryAutoplay: true))
    }
    func testNoFireWhenStillInPlaylist() {
        XCTAssertFalse(detectQueueEnd(
            prevWasRealPlaylist: true, prevAtLastTrack: true,
            prevNaturalEnd: true, nowIsLibraryAutoplay: false))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/music && swift test --filter QueueEndTests`
Expected: FAIL — `isLibraryContextName` / `detectQueueEnd` undefined.

- [ ] **Step 3: Implement (append to `PlaybackContext.swift`)**

```swift
/// True when a context name is the on-device library (where autoplay lands).
func isLibraryContextName(_ name: String) -> Bool {
    let n = name.trimmingCharacters(in: .whitespaces)
    return n == "Music" || n == "Library"
}

/// Pure queue-end guard. Fires only when a real playlist's last track ended
/// naturally and playback flipped to library autoplay — not on manual library
/// browsing or mid-playlist changes.
func detectQueueEnd(prevWasRealPlaylist: Bool, prevAtLastTrack: Bool,
                    prevNaturalEnd: Bool, nowIsLibraryAutoplay: Bool) -> Bool {
    prevWasRealPlaylist && prevAtLastTrack && prevNaturalEnd && nowIsLibraryAutoplay
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/music && swift test --filter QueueEndTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/music/Sources/TUI/Shell/PlaybackContext.swift tools/music/Tests/MusicTests/QueueEndTests.swift
git diff --cached --stat
git commit -m "$(printf 'feat(shell): pure queue-end detection guard\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Task 4: Poller runs detection + captures ended context

**Files:**
- Modify: `tools/music/Sources/TUI/Shell/PlaybackPoller.swift`

On track change: capture the prior track's art/context/natural-end *before* overwriting, fetch the new context, run the guard, and set or clear the queue-end fields.

- [ ] **Step 1: Add working state**

Add to the thread-confined fields (after `private var artLines`):

```swift
    private var lastContext: ContextQueue? = nil
    private var qEnded = false
    private var endedPlaylist = ""
    private var endedTrack = ""
    private var endedArtist = ""
    private var endedArtLines: [String] = []
```

- [ ] **Step 2: Rework the `.active` case track-change block**

Replace the `.active(let np):` body in `tick()` with:

```swift
        case .active(let np):
            stoppedPolls = 0
            let priorPos = lastPosition          // last-seen position of the PREVIOUS track
            let priorDur = lastDuration
            lastPosition = np.position
            lastDuration = np.duration
            if np.track != lastTrack {
                // Capture everything about the track we're leaving, before overwrite.
                let prevArt = artLines           // ended track's art (not yet re-extracted)
                let prevCtx = lastContext
                let prevTrack = lastTrack
                let prevArtist = lastArtist
                let prevNatural = priorDur > 0 && priorPos >= priorDur - 8

                if !prevTrack.isEmpty {
                    if history.first.map({ $0.track != prevTrack || $0.artist != prevArtist }) ?? true {
                        history.insert((track: prevTrack, artist: prevArtist), at: 0)
                        if history.count > 20 { history.removeLast() }
                    }
                }
                lastTrack = np.track
                lastArtist = np.artist

                let ctx = pollContextQueue(np: np, backend: backend)
                if ctx.tracks.isEmpty {
                    surrounding = pollAlbumTracks(for: np, backend: backend)
                    contextName = np.album
                    lastContext = nil
                } else {
                    surrounding = ctx.tracks
                    contextName = ctx.name
                    lastContext = ctx
                }
                artLines = currentTrackArtLines(width: 44, height: 22)

                // Queue-end detection: prev playlist's last track ended naturally
                // and we flipped to library autoplay.
                let fired = detectQueueEnd(
                    prevWasRealPlaylist: prevCtx.map { !isLibraryContextName($0.name) && !$0.name.isEmpty } ?? false,
                    prevAtLastTrack: prevCtx.map { $0.total > 0 && $0.currentIndex >= $0.total } ?? false,
                    prevNaturalEnd: prevNatural,
                    nowIsLibraryAutoplay: isLibraryContextName(ctx.name))
                if fired {
                    qEnded = true
                    endedPlaylist = prevCtx?.name ?? ""
                    endedTrack = prevTrack
                    endedArtist = prevArtist
                    endedArtLines = prevArt
                } else if !isLibraryContextName(ctx.name) {
                    // Re-entered a real context — clear any prior end-of-queue offer.
                    qEnded = false
                }
            }
            store.write(NowPlayingSnapshot(
                outcome: .active(np), history: history, surrounding: surrounding,
                contextName: contextName, artLines: artLines,
                queueEnded: qEnded, endedPlaylist: endedPlaylist,
                endedTrack: endedTrack, endedArtist: endedArtist, endedArtLines: endedArtLines))
```

- [ ] **Step 3: Update the `.stopped` write to carry the new fields**

Replace the `.stopped` `store.write(...)` with:

```swift
            store.write(NowPlayingSnapshot(
                outcome: .stopped, history: history, surrounding: surrounding,
                contextName: contextName, artLines: artLines,
                queueEnded: qEnded, endedPlaylist: endedPlaylist,
                endedTrack: endedTrack, endedArtist: endedArtist, endedArtLines: endedArtLines))
```

- [ ] **Step 4: Build**

Run: `cd tools/music && swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add tools/music/Sources/TUI/Shell/PlaybackPoller.swift
git diff --cached --stat
git commit -m "$(printf 'feat(shell): poller detects queue-end and captures ended context\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Task 5: Parameterize startRadioStation (seed from a given track)

**Files:**
- Modify: `tools/music/Sources/TUI/NowPlayingTUI.swift`

Radio must seed from the *remembered* ended track, not the current (autoplay) track. Split the current-track preamble from the station-building body.

- [ ] **Step 1: Refactor `startRadioStation` (`NowPlayingTUI.swift:346`)**

Replace the function header + the current-track-reading preamble (the lines that fetch `info`, parse `trackName`/`artistName`) so the body becomes a parameterized function and the no-arg version delegates. The catalog search keys off the seed artist (the body is otherwise unchanged):

```swift
/// Build + play an artist station seeded by an explicit track/artist.
func startRadioStation(seedTitle: String, seedArtist: String) -> PlaybackContext? {
    let backend = AppleScriptBackend()
    let trackName = seedTitle
    let artistName = seedArtist
    let playlistName = "__radio__ \(artistName) — \(trackName)"
    let escapedPlaylist = escapeAppleScriptString(playlistName)
    let escapedArtist = escapeAppleScriptString(artistName)
    // ... (UNCHANGED body from the original function — auth fallback, library-by-artist,
    //      catalog searchSongs(query: artistName), temp playlist, play) ...
```

No other edits inside the moved body — it already searches `searchSongs(query: artistName, limit: 25)`, which is exactly what we want now that `artistName` is the seed.

Then add the no-arg wrapper that preserves today's behavior:

```swift
/// Radio from the currently-playing track's artist (unchanged public behavior).
func startRadioStation() -> PlaybackContext? {
    let backend = AppleScriptBackend()
    guard let info = try? syncRun({
        try await backend.runMusic("return name of current track & \"|\" & artist of current track")
    }) else { return nil }
    let parts = info.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1)
    guard parts.count >= 2 else { return nil }
    return startRadioStation(seedTitle: String(parts[0]), seedArtist: String(parts[1]))
}
```

(The no-arg call sites — `Radio.run`, the global `r` key, the old now-playing TUI — are unchanged.)

- [ ] **Step 2: Build**

Run: `cd tools/music && swift build`
Expected: Build succeeds; existing `startRadioStation()` callers still compile.

- [ ] **Step 3: Commit**

```bash
git add tools/music/Sources/TUI/NowPlayingTUI.swift
git diff --cached --stat
git commit -m "$(printf 'refactor(shell): parameterize startRadioStation with an explicit seed\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Task 6: Now Playing card menu + actions + manual trigger

**Files:**
- Modify: `tools/music/Sources/TUI/Shell/NowPlayingScene.swift`
- Test: `tools/music/Tests/MusicTests/QueueEndTests.swift` (extend)

When `queueEnded` (or the user opens the menu manually), the body shows the continuation cards. Selection force-plays the choice and clears the menu.

- [ ] **Step 1: Add a key→action test**

Append to `QueueEndTests.swift`:

```swift
    func testContinuationActionMapping() {
        XCTAssertEqual(continuationAction(for: .char("r")), .radio)
        XCTAssertEqual(continuationAction(for: .char("p")), .playlist)
        XCTAssertEqual(continuationAction(for: .char("q")), .quiet)
        XCTAssertNil(continuationAction(for: .char("s")))
        XCTAssertNil(continuationAction(for: .up))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/music && swift test --filter QueueEndTests`
Expected: FAIL — `continuationAction` / `ContinuationAction` undefined.

Note: the shell resolves `r`/`q` as globals before the scene. The scene only receives `r`/`q` when the menu is *not* active (globals win) — so when the menu is up, the scene must intercept. To make the menu's keys reach the scene, the scene sets `capturesAllInput = true` while the menu is shown (existing mechanism). Add that.

- [ ] **Step 3: Implement the action enum + mapping + scene wiring**

In `NowPlayingScene.swift`, add at file scope (above the class):

```swift
enum ContinuationAction: Equatable { case radio, playlist, quiet }

func continuationAction(for key: KeyPress) -> ContinuationAction? {
    switch key {
    case .char("r"), .char("R"): return .radio
    case .char("p"), .char("P"): return .playlist
    case .char("q"), .char("Q"): return .quiet
    default: return nil
    }
}
```

Add scene state + capture flag:

```swift
    private var manualMenu = false   // user-opened menu (vs poller-detected queueEnded)
```

Add (the menu is active when the poller flagged queue-end OR the user opened it manually):

```swift
    private func menuActive(_ snapshot: NowPlayingSnapshot) -> Bool {
        snapshot.queueEnded || manualMenu
    }
    var capturesAllInput: Bool { menuShownLastFrame }
```

Because `capturesAllInput` is read by the shell without a snapshot, track it from the last render:

```swift
    private var menuShownLastFrame = false
```

Set `menuShownLastFrame = menuActive(snapshot)` at the top of `tick(snapshot:)`.

In `render`, branch: when `menuActive(snapshot)`, draw the card menu instead of the hero+UpNext. Seed = the ended track if `queueEnded`, else the current track:

```swift
        if menuActive(snapshot) {
            return renderContinuationMenu(frame: frame, snapshot: snapshot, into: out)
        }
```

Add the menu renderer (cards with the ended/current track's art for Radio & Similar; icons for Playlist & Quiet):

```swift
    private func renderContinuationMenu(frame: ShellFrame, snapshot: NowPlayingSnapshot, into base: String) -> String {
        var out = base
        let (seedTitle, art): (String, [String]) = snapshot.queueEnded
            ? (snapshot.endedTrack, snapshot.endedArtLines)
            : ({ if case .active(let np) = snapshot.outcome { return np.track } else { return "" } }(), snapshot.artLines)
        let title = snapshot.queueEnded
            ? "Queue ended — what next?"
            : "What next?"
        out += ANSICode.moveTo(row: frame.bodyY, col: 3)
        out += "\(ANSICode.bold)\(ANSICode.cyan)\(title)\(ANSICode.reset)"

        // Art thumbnail (shared by Radio/Similar cards), then a labelled option list.
        let artTop = frame.bodyY + 2
        let artRows = min(art.count, max(0, frame.bodyHeight - 8))
        for i in 0..<artRows {
            out += ANSICode.moveTo(row: artTop + i, col: 3) + "\(art[i])\(ANSICode.reset)"
        }
        let lx = 3
        var ly = artTop + artRows + 1
        let opts: [(String, String)] = [
            ("[R]", "Artist Radio  \(ANSICode.dim)from \(truncText(seedTitle, to: 28))\(ANSICode.reset)"),
            ("[P]", "Playlist  \(ANSICode.dim)browse\(ANSICode.reset)"),
            ("[Q]", "Quiet  \(ANSICode.dim)stop here\(ANSICode.reset)"),
        ]
        for (key, label) in opts {
            out += ANSICode.moveTo(row: ly, col: lx) + "\(ANSICode.lime)\(key)\(ANSICode.reset)  \(label)"
            ly += 1
        }
        return out
    }
```

Handle the menu keys in `handle` — at the TOP of the function, before the existing switch:

```swift
        // Continuation menu intercepts its keys when active.
        if menuShownLastFrame {
            if let action = continuationAction(for: key) {
                act(on: action)
                manualMenu = false           // menu dismissed; queueEnded clears when poller re-enters a real context
                return .redraw
            }
            // any other key dismisses the manual menu (auto menu stays until poller clears it)
            if case .escape = key { manualMenu = false; return .redraw }
        }
        // Manual open: 'n' (next-options) when no menu is up.
        if case .char("n") = key, !menuShownLastFrame {
            manualMenu = true; return .redraw
        }
```

Add the `act(on:)` helper (force-plays, overriding autoplay):

```swift
    private func act(on action: ContinuationAction) {
        switch action {
        case .radio:
            _ = startRadioStation(seedTitle: pendingSeedTitle, seedArtist: pendingSeedArtist)
        case .playlist:
            wantsPlaylists = true
        case .quiet:
            _ = try? syncRun { try await self.backend.runMusic("pause") }
        }
    }
```

`act` needs the seed + a way to request the Playlists scene. Capture the seed each tick and surface a pop/push request. Add fields + set them in `tick`:

```swift
    private var pendingSeedTitle = ""
    private var pendingSeedArtist = ""
    private var wantsPlaylists = false
```

In `tick(snapshot:)`, after computing `menuShownLastFrame`, set the pending seed:

```swift
        if snapshot.queueEnded {
            pendingSeedTitle = snapshot.endedTrack
            pendingSeedArtist = snapshot.endedArtist
        } else if case .active(let np) = snapshot.outcome {
            pendingSeedTitle = np.track
            pendingSeedArtist = np.artist
        }
```

For `[P]`, the scene asks the shell to switch to Playlists by returning `.push(.playlists)`. Change the menu-key handling to honor `wantsPlaylists`:

```swift
        if menuShownLastFrame {
            if let action = continuationAction(for: key) {
                act(on: action)
                manualMenu = false
                if wantsPlaylists { wantsPlaylists = false; return .push(.playlists) }
                return .redraw
            }
            if case .escape = key { manualMenu = false; return .redraw }
        }
```

- [ ] **Step 4: Run tests + build**

Run: `cd tools/music && swift test --filter QueueEndTests && swift build`
Expected: QueueEndTests PASS (7 tests); build succeeds.

- [ ] **Step 5: Commit**

```bash
git add tools/music/Sources/TUI/Shell/NowPlayingScene.swift tools/music/Tests/MusicTests/QueueEndTests.swift
git diff --cached --stat
git commit -m "$(printf 'feat(shell): end-of-queue continuation card menu + manual trigger\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Task 7: Live verification + version bump to 1.10.0

- [ ] **Step 1: Full build + test**

Run: `cd tools/music && swift build && swift test`
Expected: Build succeeds; all pass (82 + 6 QueueEnd + the extended PlaybackContext = report the count; expect ~89).

- [ ] **Step 2: Reinstall + run**

```bash
cd /Users/anthonymaley/apple-music && scripts/install.sh && music
```

- [ ] **Step 3: Verify**

- Play a short playlist to its end (let the last track finish naturally). When Apple Music autoplay would take over, the Now Playing body shows **"Queue ended — what next?"** with the ended track's art and `[R] Artist Radio · [P] Playlist · [Q] Quiet`.
- `R` starts artist radio from the ended track (not the autoplay track); `P` jumps to the Playlists scene; `Q` pauses.
- Browsing your library manually does **not** trigger the menu (the guard).
- Press `n` during normal playback → the same menu opens on demand (manual trigger), seeded from the current track; `Esc` dismisses it.
- The menu's letter keys act even though `r`/`q` are normally globals (the scene captures input while the menu is up).

Report any failure with the exact symptom — especially false triggers or the menu not appearing at a real queue-end (detection tuning).

- [ ] **Step 4: Bump to 1.10.0 (folds in the pending Now-Playing polish + this feature)**

Set all four locations to `1.10.0`:
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → `metadata.version`
- `.claude-plugin/marketplace.json` → `plugins[0].version`
- `tools/music/Sources/Music.swift:8` → `version: "1.10.0"`

```bash
cd /Users/anthonymaley/apple-music && scripts/install.sh && music --version   # expect 1.10.0
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json tools/music/Sources/Music.swift
git diff --cached --stat
git commit -m "$(printf 'chore: bump to 1.10.0 (end-of-queue continuation + Now Playing polish)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Self-Review

**Spec coverage:**
- React-don't-suppress (force-override autoplay) → Task 6 `act(on:)`. ✓
- Detection guard (real playlist · last track · natural end · → library) → Tasks 3, 4. ✓
- Snapshot ended-context incl. art captured at detection → Tasks 2, 4. ✓
- Card menu R/P/Q with ended-track art for R → Task 6. ✓
- Radio seeds the *remembered* track (startRadioStation parameterized) → Tasks 5, 6. ✓
- Manual trigger fallback (`n`) → Task 6 (spec risk #1 mitigation). ✓
- Quiet = best-effort pause → Task 6. ✓
- Deferred: **Similar** card (Radio covers the need — user call); smart suggested next playlist (P just browses); autoplay suppression; artist images. ✓

**Placeholder scan:** Task 5 says "UNCHANGED body from the original function" — this is a *relocation of existing code the engineer can read in the repo*, with the two precise edits spelled out; not a placeholder for new logic. All new code is shown in full. No TBD/TODO.

**Type consistency:** `ContextQueue`(name/currentIndex/total/tracks), `parseContextQueue`, `isLibraryContextName`, `detectQueueEnd`, snapshot fields (queueEnded/endedPlaylist/endedTrack/endedArtist/endedArtLines), `ContinuationAction`, `continuationAction`, `startRadioStation(seedTitle:seedArtist:query:)` used consistently across tasks. Reused existing: `pollContextQueue`, `pollAlbumTracks`, `currentTrackArtLines`, `extractArtwork`/`artworkToAscii` (via the former), `TrackListEntry`, `syncRun`, `ANSICode`, `truncText`, `KeyPress`, `SceneAction.push(.playlists)`.

**Risk to watch in execution:** detection tuning (the `prevNaturalEnd` threshold of 8s and the library-name check) is the part most likely to need adjustment after live testing — Step 3 calls it out explicitly.
