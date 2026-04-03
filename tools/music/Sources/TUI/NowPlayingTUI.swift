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
