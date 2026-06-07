# Unified TUI Shell — Milestone 2b (Speakers Scene) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the final v1 scene — a unified **Speakers** scene that merges the AirPlay picker and the volume mixer into one surface (toggle active membership + adjust per-speaker volume), then bump the whole unified shell to 1.9.0.

**Architecture:** One `SpeakerRow {name, active, volume}` list loaded once via the existing `fetchSpeakerDevices()`. `Enter` toggles a row's active membership; `Left`/`Right` step its volume ±5. Both fire the existing AppleScript one-liners (each its own call, per the -50 rule). The scene does **not** capture input — its bindings (Enter/←/→/↑/↓/Esc) avoid every shell global, so Space/`+`/`-`/`<`/`>`/digits/Tab/`q` keep working while you manage speakers.

**Tech Stack:** Swift 5, AppleScript via `osascript`, XCTest, raw-mode terminal.

**Reference spec:** `docs/superpowers/specs/2026-06-07-unified-tui-shell-design.md`
**Builds on:** M1 (`98b1d30…e0fa3cb`) + M2-Playlists (`29eb319…f2c684f`). The shell loop, `Scene`/`capturesAllInput`, `Router` (`SceneID.speakers` already declared), `ShellFrame`, lazy `ensureScene`.

**Working location:** `main`; commit per task, push after each.

## Scope

**In:** `SpeakerRow` model + pure mapper; `SpeakersScene` (toggle + per-speaker volume, drawn into the body); wire as shell tab #3; version bump to 1.9.0 (the unified shell release).

**Out (deferred, noted):**
- Two-digit numeric volume entry (the old mixer's feature) — Left/Right stepping covers v1; precise entry would need a capture mode, a follow-up.
- Off-main AppleScript for scene ops — toggle/volume fire inline (brief stall, consistent with `PlaylistsScene`); same "off-main scene fetching" polish already flagged.
- Retiring standalone `music speaker` / `music volume` — they stay as-is (additive).
- Live re-sync if speakers change externally while the scene is open — one-time load for v1.

---

## File Structure

New:
- `Sources/TUI/Shell/SpeakersScene.swift` — `SpeakerRow` + `speakerRows(from:)` + `SpeakersScene: Scene`.
- `Tests/MusicTests/SpeakerRowTests.swift` — pure mapper tests.

Modified:
- `Sources/TUI/Shell/Shell.swift` — register Speakers as tab #3 in `ensureScene` + `tabs`; footer hint.
- Version: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (×2), `tools/music/Sources/Music.swift:8`.

Reused existing symbols: `fetchSpeakerDevices()` (`SpeakerCommands.swift:194`, returns `[[String:Any]]` keys name/selected/volume/kind), `meterBar(value:width:)` (`TUILayout.swift:89`), `escapeAppleScriptString`, `syncRun`, `AppleScriptBackend`, `ANSICode`, `truncText`, `SceneID.speakers` (`Router.swift`).

---

## Task 1: SpeakerRow model + pure mapper

**Files:**
- Create: `tools/music/Sources/TUI/Shell/SpeakersScene.swift` (model + mapper now; scene added in Task 2)
- Test: `tools/music/Tests/MusicTests/SpeakerRowTests.swift`

`fetchSpeakerDevices()` returns `[[String:Any]]`; map it to a typed `[SpeakerRow]` via a pure function that's unit-testable without AppleScript.

- [ ] **Step 1: Write the failing test**

```swift
// tools/music/Tests/MusicTests/SpeakerRowTests.swift
import XCTest
@testable import music

final class SpeakerRowTests: XCTestCase {
    func testMapsDeviceDicts() {
        let devices: [[String: Any]] = [
            ["name": "Kitchen", "selected": true, "volume": 58, "kind": "AirPlay"],
            ["name": "Office", "selected": false, "volume": 30, "kind": "AirPlay"],
        ]
        let rows = speakerRows(from: devices)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].name, "Kitchen")
        XCTAssertTrue(rows[0].active)
        XCTAssertEqual(rows[0].volume, 58)
        XCTAssertFalse(rows[1].active)
        XCTAssertEqual(rows[1].volume, 30)
    }
    func testSkipsMalformedEntries() {
        let devices: [[String: Any]] = [
            ["name": "Good", "selected": true, "volume": 50, "kind": "AirPlay"],
            ["selected": true, "volume": 50],            // missing name
            ["name": "NoVol", "selected": false],         // missing volume
        ]
        let rows = speakerRows(from: devices)
        XCTAssertEqual(rows.map { $0.name }, ["Good"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/music && swift test --filter SpeakerRowTests`
Expected: FAIL — `SpeakerRow` / `speakerRows` undefined.

- [ ] **Step 3: Write the model + mapper**

```swift
// tools/music/Sources/TUI/Shell/SpeakersScene.swift
import Foundation

/// One AirPlay output: its name, whether it's in the active group, and its volume.
struct SpeakerRow {
    let name: String
    var active: Bool
    var volume: Int
}

/// Pure mapping from `fetchSpeakerDevices()`'s `[[String:Any]]` to typed rows.
/// Entries missing name/selected/volume are skipped.
func speakerRows(from devices: [[String: Any]]) -> [SpeakerRow] {
    devices.compactMap { d in
        guard let name = d["name"] as? String,
              let active = d["selected"] as? Bool,
              let volume = d["volume"] as? Int else { return nil }
        return SpeakerRow(name: name, active: active, volume: volume)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/music && swift test --filter SpeakerRowTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/music/Sources/TUI/Shell/SpeakersScene.swift tools/music/Tests/MusicTests/SpeakerRowTests.swift
git diff --cached --stat   # confirm ONLY these two files; docs/playlist-browser-ui.md must NOT appear
git commit -m "$(printf 'feat(shell): SpeakerRow model + pure mapper\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Task 2: SpeakersScene

**Files:**
- Modify: `tools/music/Sources/TUI/Shell/SpeakersScene.swift` (append the scene to the file from Task 1)

Loads rows once (inline on first `tick`, `loaded` gate — brief one-time stall, consistent with `PlaylistsScene`). `Enter` toggles active; `Left`/`Right` step volume ±5; both update the row in memory and fire the AppleScript inline. Does not override `capturesAllInput` (stays `false`), so all shell globals remain live.

- [ ] **Step 1: Append the scene class**

```swift

final class SpeakersScene: Scene {
    let id: SceneID = .speakers
    let tabTitle = "Speakers"

    private let backend: AppleScriptBackend
    private var rows: [SpeakerRow] = []
    private var cursor = 0
    private var loaded = false

    init(backend: AppleScriptBackend) { self.backend = backend }

    func tick(snapshot: NowPlayingSnapshot) {
        // One-time load (brief stall on first open; off-main is future polish).
        if !loaded {
            loaded = true
            rows = speakerRows(from: (try? fetchSpeakerDevices()) ?? [])
            if cursor >= rows.count { cursor = max(0, rows.count - 1) }
        }
    }

    func render(frame: ShellFrame, snapshot: NowPlayingSnapshot) -> String {
        var out = ""
        for r in frame.bodyY..<(frame.bodyY + frame.bodyHeight) {
            out += ANSICode.moveTo(row: r, col: 1) + ANSICode.clearLine
        }
        var y = frame.bodyY
        out += ANSICode.moveTo(row: y, col: 3)
        out += "\(ANSICode.bold)\(ANSICode.cyan)AirPlay Outputs\(ANSICode.reset)"
        y += 2

        if rows.isEmpty {
            out += ANSICode.moveTo(row: y, col: 3) + "\(ANSICode.dim)No AirPlay outputs found.\(ANSICode.reset)"
            return out
        }

        let nameW = 18
        let barW = 16
        let bottom = frame.bodyY + frame.bodyHeight - 1
        for (i, row) in rows.enumerated() {
            guard y <= bottom else { break }
            out += ANSICode.moveTo(row: y, col: 3)
            let isCursor = i == cursor
            let marker = isCursor ? "\(ANSICode.cyan)\u{25B8}\(ANSICode.reset)" : " "
            let dot = row.active ? "\(ANSICode.lime)\u{25CF}\(ANSICode.reset)" : "\(ANSICode.dim)\u{25CB}\(ANSICode.reset)"
            let name = truncText(row.name, to: nameW)
            let padName = name + String(repeating: " ", count: max(0, nameW - name.count))
            let nameStr = row.active
                ? "\(ANSICode.brightWhite)\(padName)\(ANSICode.reset)"
                : "\(ANSICode.dim)\(padName)\(ANSICode.reset)"
            let bar = meterBar(value: row.volume, width: barW)
            let vol = String(format: "%3d", row.volume)
            out += "\(marker) \(dot) \(nameStr) \(bar) \(vol)"
            y += 1
        }

        // Hint inside the body.
        if y + 1 <= bottom {
            out += ANSICode.moveTo(row: y + 1, col: 3)
            out += "\(ANSICode.dim)Enter toggle active   \u{2190}\u{2192} volume   Esc back\(ANSICode.reset)"
        }
        return out
    }

    func handle(_ key: KeyPress) -> SceneAction {
        guard !rows.isEmpty else {
            if case .escape = key { return .pop }
            return .none
        }
        switch key {
        case .up:
            cursor = max(0, cursor - 1); return .redraw
        case .down:
            cursor = min(rows.count - 1, cursor + 1); return .redraw
        case .enter:
            rows[cursor].active.toggle()
            setSelected(rows[cursor])
            return .redraw
        case .left:
            rows[cursor].volume = max(0, rows[cursor].volume - 5)
            setVolume(rows[cursor])
            return .redraw
        case .right:
            rows[cursor].volume = min(100, rows[cursor].volume + 5)
            setVolume(rows[cursor])
            return .redraw
        case .escape:
            return .pop
        default:
            return .none
        }
    }

    // MARK: AppleScript (each its own call — never batched, per the -50 rule)

    private func setSelected(_ row: SpeakerRow) {
        let esc = escapeAppleScriptString(row.name)
        _ = try? syncRun { try await self.backend.runMusic("set selected of AirPlay device \"\(esc)\" to \(row.active)") }
    }
    private func setVolume(_ row: SpeakerRow) {
        let esc = escapeAppleScriptString(row.name)
        let v = row.volume
        _ = try? syncRun { try await self.backend.runMusic("set sound volume of AirPlay device \"\(esc)\" to \(v)") }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd tools/music && swift build`
Expected: Builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add tools/music/Sources/TUI/Shell/SpeakersScene.swift
git diff --cached --stat   # confirm ONLY this file
git commit -m "$(printf 'feat(shell): SpeakersScene (merged picker + per-speaker volume)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Task 3: Wire the Speakers tab into the shell

**Files:**
- Modify: `tools/music/Sources/TUI/Shell/Shell.swift`

Add Speakers as tab #3 and build it lazily. Unlike Playlists, the Speakers scene always builds (no precondition — an empty list renders "No AirPlay outputs found").

- [ ] **Step 1: Add to the tabs list**

In `tools/music/Sources/TUI/Shell/Shell.swift`, change the `tabs` declaration (from M2-Playlists):

```swift
    let tabs: [(id: SceneID, title: String)] = [(.nowPlaying, "Now"), (.playlists, "Playlists")]
```

to:

```swift
    let tabs: [(id: SceneID, title: String)] = [(.nowPlaying, "Now"), (.playlists, "Playlists"), (.speakers, "Speakers")]
```

- [ ] **Step 2: Add the `.speakers` case to `ensureScene`**

In the `ensureScene(_:)` function, add a case before `default:`:

```swift
        case .speakers:
            let scene = SpeakersScene(backend: backend)
            scenes[id] = scene
            return scene
```

- [ ] **Step 3: Update the footer hint**

Replace the footer hint string (from M2-Playlists) with:

```swift
            out += "\(ANSICode.dim)1 Now  2 Playlists  3 Speakers  Tab Switch   \u{2191}\u{2193} Move  Enter Select  q Quit\(ANSICode.reset)"
```

- [ ] **Step 4: Full build + test**

Run: `cd tools/music && swift build && swift test`
Expected: Build succeeds; all pass (78 + 2 from Task 1 = 80).

- [ ] **Step 5: Commit**

```bash
git add tools/music/Sources/TUI/Shell/Shell.swift
git diff --cached --stat   # confirm ONLY this file
git commit -m "$(printf 'feat(shell): wire Speakers as tab 3\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Task 4: Live verification + version bump to 1.9.0

- [ ] **Step 1: Reinstall + run**

```bash
cd /Users/anthonymaley/apple-music && scripts/install.sh && music
```

- [ ] **Step 2: Verify (with music playing)**

- Tab strip shows `Now  Playlists  Speakers`; `3` or `Tab` reaches Speakers; bar still ticking.
- Speakers list shows every AirPlay output with a `●` (active) / `○` (inactive) dot, name, volume meter, and number.
- `↑`/`↓` move the cursor; `Enter` toggles a speaker's active dot (and you hear it join/leave); the now-playing bar's speaker line updates within ~1s.
- `←`/`→` step the highlighted speaker's volume; the meter moves; the device's real volume changes.
- **Globals still work in this scene:** `Space` pauses, `</>` change track, `1`/`2` jump to Now/Playlists, `q` quits — none are swallowed (the scene doesn't capture input).
- `Esc` leaves the Speakers scene.
- `music speaker` and `music volume` (the commands) still open their standalone TUIs unchanged.

Report any failure with the exact symptom.

- [ ] **Step 3: After verification passes — bump to 1.9.0**

Set version in all four locations (CLAUDE.md Version Strategy):
- `.claude-plugin/plugin.json` → `version` → `1.9.0`
- `.claude-plugin/marketplace.json` → `metadata.version` → `1.9.0`
- `.claude-plugin/marketplace.json` → `plugins[0].version` → `1.9.0`
- `tools/music/Sources/Music.swift:8` → `version: "1.9.0"`

```bash
cd /Users/anthonymaley/apple-music && scripts/install.sh && music --version   # expect 1.9.0
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json tools/music/Sources/Music.swift
git diff --cached --stat   # confirm ONLY these three files
git commit -m "$(printf 'chore: bump to 1.9.0 (unified TUI shell: Now Playing + Playlists + Speakers)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
git push
```

---

## Self-Review

**Spec coverage (M2b-Speakers scope):**
- Speakers scene merging picker + mixer → Tasks 1-2. ✓
- Toggle active + per-speaker volume via reused AppleScript one-liners (separate calls, -50 rule) → Task 2. ✓
- Globals remain live (no input capture; bindings avoid all globals) → Task 2 design. ✓
- Wired as tab #3, lazy build → Task 3. ✓
- Unified shell v1 complete (Now Playing + Playlists + Speakers) → version bump 1.9.0, Task 4. ✓
- Deferred + flagged: two-digit volume entry; off-main scene ops; retiring `music speaker`/`music volume`; external-change live re-sync. ✓

**Placeholder scan:** No TBD/TODO; complete code in every code step; exact commands + expected output. ✓

**Type consistency:** `SpeakerRow`(name/active/volume), `speakerRows(from:)`, `SpeakersScene`(id/tabTitle/tick/render/handle), `setSelected`/`setVolume`. Reused symbols verified against source: `fetchSpeakerDevices()` (`SpeakerCommands.swift:194`, `[[String:Any]]` keys name/selected/volume/kind), `meterBar(value:width:)` (`TUILayout.swift:89`), `escapeAppleScriptString`, `syncRun`, `AppleScriptBackend.runMusic`, `ANSICode`, `truncText`, `SceneID.speakers`, `ensureScene`. ✓

**Behavior-change notes (intentional, in-plan):**
- Toggle is `Enter` (was `Space` in the old picker) and there is no two-digit volume entry — deliberate so the scene needs no `capturesAllInput`, keeping all shell globals (Space/`+`/`-`/`<`/`>`/digits/Tab/`q`) live while managing speakers.
- Toggle/volume AppleScript runs inline on the main loop (brief stall per action), consistent with `PlaylistsScene`; off-main is the shared future polish.
- Speakers list is loaded once on first open; external changes mid-session aren't re-synced (the now-playing bar still reflects active-set changes via the poller).
