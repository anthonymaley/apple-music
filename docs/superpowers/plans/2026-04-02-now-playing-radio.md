# Interactive Now Playing + Radio Station — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an interactive now-playing TUI with a real-time timeline bar and playback controls, plus a `music radio` command that starts an Apple Music station from the current track.

**Architecture:** Extends the existing TUI framework (`Terminal.swift`, `VolumeMixer.swift` pattern) with a timed key-read for auto-refresh. New `NowPlayingTUI.swift` handles the render loop. `Radio` is a standalone command struct + slash command, also wired as `r` key in the TUI.

**Tech Stack:** Swift 5.9+, ArgumentParser, AppleScript via `osascript`, POSIX `poll()` for non-blocking stdin reads.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `Sources/TUI/Terminal.swift` | Add `KeyPress.read(timeout:)` using `poll()` |
| `Sources/TUI/NowPlayingTUI.swift` | New: render loop, polling, key handling |
| `Sources/Commands/PlaybackCommands.swift` | Add `Radio` command struct, add TUI gate to `Now.run()` |
| `Sources/Music.swift` | Register `Radio` subcommand |
| `commands/radio.md` | New slash command `/music:radio` |

---

### Task 1: Add timeout to KeyPress.read()

**Files:**
- Modify: `tools/music/Sources/TUI/Terminal.swift:28-64`

- [ ] **Step 1: Add `KeyPress.read(timeout:)` with `poll()`**

Add a new static method that uses POSIX `poll()` to wait for stdin with a timeout. The existing `read()` stays unchanged (infinite block). The new overload returns `nil` on timeout.

```swift
/// Read a keypress with a timeout in seconds. Returns nil if no key pressed within timeout.
static func read(timeout: Double) -> KeyPress? {
    var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    let ms = Int32(timeout * 1000)
    let ready = poll(&pfd, 1, ms)
    guard ready > 0, pfd.revents & Int16(POLLIN) != 0 else { return nil }
    return read()
}
```

Add this inside `enum KeyPress`, right after the existing `static func read() -> KeyPress?` method (after line 64, before the closing `}`).

- [ ] **Step 2: Add `r` to the char mapping**

The existing `read()` already maps `0x72` → `r` implicitly via the `default` case. Confirm `char("r")` works by checking: `0x72` falls through to `Unicode.Scalar(buf[0])` → `Character("r")` → `.char("r")`. No change needed — it already works.

- [ ] **Step 3: Build to verify**

```bash
cd tools/music && swift build
```

Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/anthonymaley/apple-music
git add tools/music/Sources/TUI/Terminal.swift
git commit -m "feat: add timeout parameter to KeyPress.read() for polling TUIs"
```

---

### Task 2: Create NowPlayingTUI

**Files:**
- Create: `tools/music/Sources/TUI/NowPlayingTUI.swift`

- [ ] **Step 1: Create the file with the full render + poll loop**

Create `tools/music/Sources/TUI/NowPlayingTUI.swift`:

```swift
import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct NowPlayingState {
    var track: String = ""
    var artist: String = ""
    var album: String = ""
    var duration: Int = 0
    var position: Int = 0
    var state: String = "stopped"
    var speakers: [(name: String, volume: Int)] = []
}

func pollNowPlaying() -> NowPlayingState? {
    let backend = AppleScriptBackend()
    guard let result = try? syncRun({
        try await backend.runMusic("""
            try
                set state to player state as text
                if state is "stopped" then return "STOPPED"
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set d to duration of current track
                set p to player position
                set spk to ""
                set deviceList to every AirPlay device
                repeat with dev in deviceList
                    if selected of dev then
                        if spk is not "" then set spk to spk & ","
                        set spk to spk & name of dev & ":" & sound volume of dev
                    end if
                end repeat
                return t & "|" & a & "|" & al & "|" & (round d) & "|" & (round p) & "|" & state & "|" & spk
            end try
            return "STOPPED"
        """)
    }) else { return nil }

    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "STOPPED" { return nil }
    let parts = trimmed.split(separator: "|", maxSplits: 6).map(String.init)
    guard parts.count >= 7 else { return nil }

    let speakers = parts[6].split(separator: ",").map { pair -> (name: String, volume: Int) in
        let kv = pair.split(separator: ":", maxSplits: 1)
        return (name: String(kv[0]), volume: Int(kv.count > 1 ? String(kv[1]) : "0") ?? 0)
    }

    return NowPlayingState(
        track: parts[0], artist: parts[1], album: parts[2],
        duration: Int(parts[3]) ?? 0, position: Int(parts[4]) ?? 0,
        state: parts[5], speakers: speakers
    )
}

func formatTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}

func startRadioStation() {
    let backend = AppleScriptBackend()
    _ = try? syncRun {
        try await backend.runMusic("""
            set t to current track
            set trackName to name of t
            set trackArtist to artist of t
            tell application "System Events"
                tell process "Music"
                    click menu item "Create Station" of menu "Song" of menu bar 1
                end tell
            end tell
        """)
    }
}

func runNowPlayingTUI() {
    let terminal = TerminalState.shared
    terminal.enterRawMode()
    defer { terminal.exitRawMode() }

    let barWidth = 30

    func render(_ np: NowPlayingState) {
        var out = ANSICode.cursorHome + ANSICode.clearScreen

        // Header
        let icon = np.state == "paused" ? "⏸" : "♫"
        out += "\n"
        out += "  \(ANSICode.bold)\(ANSICode.cyan)\(icon)  Now Playing\(ANSICode.reset)\n"
        out += "  \(ANSICode.dim)\(String(repeating: "─", count: 40))\(ANSICode.reset)\n\n"

        // Track info
        out += "  \(ANSICode.bold)\(np.track) — \(np.artist)\(ANSICode.reset)\n"
        out += "  \(ANSICode.dim)\(np.album)\(ANSICode.reset)\n\n"

        // Timeline bar
        let fraction = np.duration > 0 ? Double(np.position) / Double(np.duration) : 0
        let filled = Int(fraction * Double(barWidth))
        let bar = "\(ANSICode.green)\(String(repeating: "█", count: filled))\(ANSICode.reset)\(ANSICode.dim)\(String(repeating: "░", count: barWidth - filled))\(ANSICode.reset)"
        out += "  \(bar)  \(formatTime(np.position)) / \(formatTime(np.duration))\n\n"

        // Speakers
        if !np.speakers.isEmpty {
            let spkStr = np.speakers.map { "\($0.name) [\($0.volume)]" }.joined(separator: "  ·  ")
            out += "  \(ANSICode.dim)\(spkStr)\(ANSICode.reset)\n\n"
        }

        // Footer
        out += "  \(ANSICode.dim)╭────────────────────────────────────────────╮\(ANSICode.reset)\n"
        out += "  \(ANSICode.dim)│\(ANSICode.reset) ←→ skip  ␣ pause/resume  r radio  q quit \(ANSICode.dim)│\(ANSICode.reset)\n"
        out += "  \(ANSICode.dim)╰────────────────────────────────────────────╯\(ANSICode.reset)\n"

        print(out, terminator: "")
        fflush(stdout)
    }

    func renderStopped() {
        var out = ANSICode.cursorHome + ANSICode.clearScreen
        out += "\n"
        out += "  \(ANSICode.bold)\(ANSICode.cyan)♫  Now Playing\(ANSICode.reset)\n"
        out += "  \(ANSICode.dim)\(String(repeating: "─", count: 40))\(ANSICode.reset)\n\n"
        out += "  \(ANSICode.dim)Nothing playing.\(ANSICode.reset)\n\n"
        out += "  \(ANSICode.dim)╭──────────────────╮\(ANSICode.reset)\n"
        out += "  \(ANSICode.dim)│\(ANSICode.reset) q quit            \(ANSICode.dim)│\(ANSICode.reset)\n"
        out += "  \(ANSICode.dim)╰──────────────────╯\(ANSICode.reset)\n"
        print(out, terminator: "")
        fflush(stdout)
    }

    // Initial render
    let backend = AppleScriptBackend()
    if let np = pollNowPlaying() {
        render(np)
    } else {
        renderStopped()
    }

    while true {
        let key = KeyPress.read(timeout: 1.0)

        if let key = key {
            switch key {
            case .left:
                _ = try? syncRun { try await backend.runMusic("previous track") }
            case .right:
                _ = try? syncRun { try await backend.runMusic("next track") }
            case .space:
                _ = try? syncRun { try await backend.runMusic("playpause") }
            case .char("r"):
                startRadioStation()
            case .char("q"), .escape:
                return
            default:
                break
            }
        }

        // Re-poll and render
        if let np = pollNowPlaying() {
            render(np)
        } else {
            renderStopped()
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd tools/music && swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/anthonymaley/apple-music
git add tools/music/Sources/TUI/NowPlayingTUI.swift
git commit -m "feat: add interactive now-playing TUI with timeline bar"
```

---

### Task 3: Wire up Now command and add Radio command

**Files:**
- Modify: `tools/music/Sources/Commands/PlaybackCommands.swift:143-149`
- Modify: `tools/music/Sources/Music.swift:9-36`

- [ ] **Step 1: Add TUI gate to Now.run()**

In `tools/music/Sources/Commands/PlaybackCommands.swift`, replace the `Now` struct (lines 143-149):

```swift
struct Now: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show what's currently playing.")
    @Flag(name: .long, help: "Output JSON") var json = false
    func run() throws {
        if isBareInvocation(command: "now") && isTTY() {
            runNowPlayingTUI()
            return
        }
        showNowPlaying(json: json)
    }
}
```

- [ ] **Step 2: Add Radio command struct**

Append this after the `Repeat_` struct at the end of `PlaybackCommands.swift` (before the `syncRun` function):

```swift
struct Radio: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start a radio station from the current track.")
    func run() throws {
        let backend = AppleScriptBackend()
        let info = try syncRun {
            try await backend.runMusic("return name of current track & \" — \" & artist of current track")
        }
        let trackInfo = info.trimmingCharacters(in: .whitespacesAndNewlines)
        startRadioStation()
        print("Started radio station from: \(trackInfo)")
    }
}
```

- [ ] **Step 3: Register Radio in Music.swift**

In `tools/music/Sources/Music.swift`, add `Radio.self` to the subcommands array, after `Repeat_.self` in the Playback section:

```swift
            // Playback
            Play.self,
            Pause.self,
            Skip.self,
            Back.self,
            Stop.self,
            Now.self,
            Shuffle.self,
            Repeat_.self,
            Radio.self,
```

- [ ] **Step 4: Build to verify**

```bash
cd tools/music && swift build
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
cd /Users/anthonymaley/apple-music
git add tools/music/Sources/Commands/PlaybackCommands.swift tools/music/Sources/Music.swift
git commit -m "feat: wire Now TUI gate and add Radio command"
```

---

### Task 4: Create /music:radio slash command

**Files:**
- Create: `commands/radio.md`

- [ ] **Step 1: Create the slash command file**

Create `commands/radio.md`:

```markdown
---
name: radio
description: "Start a radio station from the currently playing track"
disable-model-invocation: true
---

!`MUSIC_CLI="${MUSIC_CLI:-music}"
if command -v "$MUSIC_CLI" &>/dev/null; then
    $MUSIC_CLI radio
else
    TRACK=$(osascript -e 'tell application "Music" to return name of current track & " — " & artist of current track' 2>/dev/null)
    if [ -z "$TRACK" ]; then
        echo "Nothing playing."
        exit 0
    fi
    osascript -e '
        tell application "System Events"
            tell process "Music"
                click menu item "Create Station" of menu "Song" of menu bar 1
            end tell
        end tell
    ' 2>/dev/null
    echo "Started radio station from: $TRACK"
fi`
```

- [ ] **Step 2: Commit**

```bash
cd /Users/anthonymaley/apple-music
git add commands/radio.md
git commit -m "feat: add /music:radio slash command"
```

---

### Task 5: Install, test, and fix radio AppleScript

**Files:**
- Possibly modify: `tools/music/Sources/TUI/NowPlayingTUI.swift` (the `startRadioStation()` function)

The spec notes that the exact AppleScript for station creation needs hands-on testing. The `System Events` menu-click approach may need adjustment depending on macOS version and menu item names.

- [ ] **Step 1: Build and install**

```bash
cd tools/music && swift build && cp .build/debug/music ~/.local/bin/music
```

- [ ] **Step 2: Test `music radio` from a real terminal**

Play a song first, then run:

```bash
music radio
```

Expected: Music app starts a radio station seeded from the current track. Output: `Started radio station from: Track — Artist`

If the `System Events` approach fails (common issues: menu item name differs, accessibility permissions needed), try these alternatives in order:

**Alternative A** — Use `open location` with the track's store URL:
```applescript
tell application "Music"
    set t to current track
    open location "itmss://music.apple.com/station/ra." & (database ID of t as text)
end tell
```

**Alternative B** — Use `open location` with a search-based station URL:
```applescript
tell application "Music"
    set trackName to name of current track
    set trackArtist to artist of current track
    open location "music://music.apple.com/search?term=" & trackName & " " & trackArtist
end tell
```

**Alternative C** — Use AppleScript `play` with station creation:
```applescript
tell application "Music"
    set t to current track
    set s to (make new station with properties {name:name of t})
    play s
end tell
```

Update `startRadioStation()` in `NowPlayingTUI.swift` with whichever approach works.

- [ ] **Step 3: Test `music now` interactive TUI from a real terminal**

```bash
music now
```

Expected: Interactive display with timeline bar updating every second. Test:
- `←` skips to previous track
- `→` skips to next track
- `space` pauses/resumes (header icon changes ♫ ↔ ⏸)
- `r` starts a radio station
- `q` exits cleanly (terminal restored)

- [ ] **Step 4: Test `/music:radio` slash command from Claude Code**

```
/music:radio
```

Expected: Prints "Started radio station from: Track — Artist"

- [ ] **Step 5: Commit any fixes from testing**

```bash
cd /Users/anthonymaley/apple-music
git add -A
git commit -m "fix: radio station AppleScript verified and working"
```

---

### Task 6: Update docs

**Files:**
- Modify: `README.md`
- Modify: `docs/guide.md`
- Modify: `skills/music/SKILL.md`

- [ ] **Step 1: Add `/music:radio` to README slash commands table**

In `README.md`, add to the Playback table (after the `/music:shuffle` row):

```markdown
| `/music:radio` | Start a radio station from what's playing |
```

- [ ] **Step 2: Add `music radio` to README CLI section**

Not needed — `music radio` doesn't require auth (it's AppleScript-only). But the CLI section is inside the auth banner. Add it to the slash commands table only, since it works without auth.

- [ ] **Step 3: Update Interactive TUI section in README**

Add a now-playing mockup after the existing volume mixer example:

```markdown
**Now playing** — real-time timeline, skip with ←→, pause with space, start radio with r:

\```
  ♫  Now Playing

  Everything In Its Right Place — Radiohead
  Kid A

  ██████████████░░░░░░░░░░░░░░░░  2:14 / 4:56

  Kitchen [60]  ·  Sonos Arc [40]

  ╭────────────────────────────────────────────╮
  │ ←→ skip  ␣ pause/resume  r radio  q quit   │
  ╰────────────────────────────────────────────╯
\```
```

- [ ] **Step 4: Add `music radio` to SKILL.md Playback section**

In `skills/music/SKILL.md`, add after the `music repeat` line:

```bash
music radio                                   # start radio station from current track
```

- [ ] **Step 5: Add to guide.md slash commands section**

In `docs/guide.md`, add to the Playback section:

```
/music:radio                     Start radio station from current track
```

- [ ] **Step 6: Commit docs**

```bash
cd /Users/anthonymaley/apple-music
git add README.md docs/guide.md skills/music/SKILL.md
git commit -m "docs: add radio command and now-playing TUI to README, guide, and skill"
```

---

### Task 7: Final build, install, push

- [ ] **Step 1: Final build and install**

```bash
cd tools/music && swift build && cp .build/debug/music ~/.local/bin/music
```

- [ ] **Step 2: Push all commits**

```bash
cd /Users/anthonymaley/apple-music && git push
```
