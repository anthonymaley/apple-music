import Foundation
import CoreGraphics
import ImageIO
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

struct TrackListEntry {
    let index: Int
    let name: String
    let artist: String
    let isCurrent: Bool
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

func pollSurroundingTracks() -> [TrackListEntry] {
    let backend = AppleScriptBackend()
    guard let result = try? syncRun({
        try await backend.runMusic("""
            try
                set cp to current playlist
                set ct to current track
                set idx to index of ct
                set total to count of tracks of cp
                set output to ""
                set startIdx to idx - 4
                if startIdx < 1 then set startIdx to 1
                set endIdx to idx + 4
                if endIdx > total then set endIdx to total
                repeat with i from startIdx to endIdx
                    set t to track i of cp
                    if output is not "" then set output to output & linefeed
                    if i = idx then
                        set output to output & ">" & i & "|" & name of t & "|" & artist of t
                    else
                        set output to output & " " & i & "|" & name of t & "|" & artist of t
                    end if
                end repeat
                return output
            end try
            return ""
        """)
    }) else { return [] }

    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    return trimmed.components(separatedBy: "\n").compactMap { line in
        let isCurrent = line.hasPrefix(">")
        let clean = String(line.dropFirst()) // drop > or space
        let parts = clean.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count >= 3, let idx = Int(parts[0]) else { return nil }
        return TrackListEntry(index: idx, name: parts[1], artist: parts[2], isCurrent: isCurrent)
    }
}

func extractArtwork() -> String? {
    let artPath = "/tmp/music-now-art.dat"
    let backend = AppleScriptBackend()
    guard let result = try? syncRun({
        try await backend.runMusic("""
            try
                set artworks_ to artworks of current track
                if (count of artworks_) > 0 then
                    set artData to raw data of item 1 of artworks_
                    set filePath to "\(artPath)"
                    set fileRef to open for access POSIX file filePath with write permission
                    set eof of fileRef to 0
                    write artData to fileRef
                    close access fileRef
                    return "OK"
                end if
            end try
            return "NONE"
        """)
    }) else { return nil }
    if result.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" {
        return artPath
    }
    return nil
}

func artworkToAscii(path: String, width: Int = 20, height: Int = 10) -> [String] {
    // Try chafa first (true color, half-block characters)
    if let chafaPath = findExecutable("chafa") {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: chafaPath)
        proc.arguments = [
            "--format", "symbols",
            "--size", "\(width)x\(height)",
            "--symbols", "block+border+space",
            "--color-space", "rgb",
            "--work", "9",
            path
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                return output.components(separatedBy: "\n").filter { !$0.isEmpty }
            }
        } catch {}
    }

    // Fallback: CoreGraphics brightness mapping
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }

    let w = width
    let h = height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = w * bytesPerPixel
    var pixelData = [UInt8](repeating: 0, count: h * bytesPerRow)

    guard let context = CGContext(
        data: &pixelData, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return [] }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

    let blocks: [Character] = [" ", "░", "▒", "▓", "█"]
    var lines: [String] = []

    for y in 0..<h {
        var line = ""
        for x in 0..<w {
            let offset = ((h - 1 - y) * bytesPerRow) + (x * bytesPerPixel)
            let r = Int(pixelData[offset])
            let g = Int(pixelData[offset + 1])
            let b = Int(pixelData[offset + 2])
            let brightness = (r + g + b) / 3
            let idx = min(blocks.count - 1, brightness * blocks.count / 256)
            line.append(blocks[idx])
        }
        lines.append(line)
    }
    return lines
}

func findExecutable(_ name: String) -> String? {
    let paths = [
        "/opt/homebrew/bin/\(name)",
        "/usr/local/bin/\(name)",
        "/usr/bin/\(name)"
    ]
    for path in paths {
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }
    return nil
}

func formatTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}

func startRadioStation() {
    let backend = AppleScriptBackend()
    // Get current track info
    guard let info = try? syncRun({
        try await backend.runMusic("return name of current track & \"|\" & artist of current track")
    }) else { return }
    let parts = info.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1)
    guard parts.count >= 2 else { return }
    let trackName = String(parts[0])
    let artistName = String(parts[1])

    // Search catalog for the artist to build a radio-like playlist
    let auth = try? AuthManager()
    guard let devToken = try? auth?.requireDeveloperToken(),
          let userToken = try? auth?.requireUserToken() else {
        // No auth — fall back to playing more by the same artist from library
        _ = try? syncRun {
            try await backend.runMusic("""
                set artistTracks to (every track of playlist "Library" whose artist contains "\(artistName.replacingOccurrences(of: "\"", with: "\\\""))")
                set shuffle enabled to true
                play item 1 of artistTracks
            """)
        }
        return
    }

    let api = RESTAPIBackend(developerToken: devToken, userToken: userToken, storefront: auth!.storefront())

    // Search for more songs by the same artist
    guard let songs = try? syncRun({ try await api.searchSongs(query: artistName, limit: 25) }),
          !songs.isEmpty else { return }

    // Create a temp playlist and shuffle it
    let playlistName = "__radio__\(trackName)"
    _ = try? syncRun {
        try await backend.runMusic("make new playlist with properties {name:\"\(playlistName.replacingOccurrences(of: "\"", with: "\\\""))\"}")
    }

    // Add songs to library first, then to playlist
    let ids = songs.map { $0.id }
    try? syncRun { try await api.addToLibrary(songIDs: ids) }
    try? syncRun { try await Task.sleep(nanoseconds: 4_000_000_000) }

    for song in songs {
        let et = song.title.replacingOccurrences(of: "\"", with: "\\\"")
        let ea = song.artist.replacingOccurrences(of: "\"", with: "\\\"")
        _ = try? syncRun {
            try await backend.runMusic("""
                set results to (every track of playlist "Library" whose name is "\(et)" and artist is "\(ea)")
                if (count of results) = 0 then
                    set results to (every track of playlist "Library" whose name contains "\(et)" and artist contains "\(ea)")
                end if
                if (count of results) > 0 then
                    duplicate item 1 of results to playlist "\(playlistName.replacingOccurrences(of: "\"", with: "\\\""))"
                end if
            """)
        }
    }

    // Shuffle play the radio playlist
    _ = try? syncRun { try await backend.runMusic("set shuffle enabled to true") }
    _ = try? syncRun { try await backend.runMusic("play playlist \"\(playlistName.replacingOccurrences(of: "\"", with: "\\\""))\"") }
}

func runNowPlayingTUI() {
    let terminal = TerminalState.shared
    terminal.enterRawMode()
    defer { terminal.exitRawMode() }

    // --- Layout computation ---
    var ws = winsize()
    _ = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws)
    let termWidth = Int(ws.ws_col) > 0 ? Int(ws.ws_col) : 120
    let termHeight = Int(ws.ws_row) > 0 ? Int(ws.ws_row) : 30

    let contentX = 3
    let contentY = 2
    let contentWidth = termWidth - 4

    let gap1 = 2
    let gap2 = 4
    let artW = max(24, min(30, contentWidth * 24 / 100))
    let metaW = max(28, min(36, contentWidth * 28 / 100))
    let queueW = contentWidth - artW - metaW - gap1 - gap2

    let artX = contentX
    let metaX = artX + artW + gap1
    let queueX = metaX + metaW + gap2

    let sectionY = contentY + 1
    let contentTopY = sectionY + 3

    let artSize = min(artW, 26, termHeight - contentTopY - 6)
    let barW = max(10, metaW - 10)

    let footerY = termHeight - 1

    var trackList: [TrackListEntry] = []
    var artLines: [String] = []
    var lastTrackName = ""

    func truncate(_ s: String, to width: Int) -> String {
        if s.count <= width { return s }
        return String(s.prefix(width - 1)) + "…"
    }

    func render(_ np: NowPlayingState) {
        var out = ANSICode.cursorHome + ANSICode.clearScreen

        // --- Top bar ---
        out += ANSICode.moveTo(row: contentY, col: contentX)
        out += "\(ANSICode.dim)\(ANSICode.bold)music\(ANSICode.reset)"

        // --- Section headers ---
        out += ANSICode.moveTo(row: sectionY, col: artX)
        out += "\(ANSICode.cyan)Now Playing\(ANSICode.reset)"

        if queueW >= 24 {
            out += ANSICode.moveTo(row: sectionY, col: queueX)
            out += "\(ANSICode.cyan)Queue\(ANSICode.reset)"
        }

        // --- Section rules ---
        let npRuleW = min(artW + metaW + gap1 - 2, 28)
        out += ANSICode.moveTo(row: sectionY + 1, col: artX)
        out += "\(ANSICode.dim)\(String(repeating: "─", count: npRuleW))\(ANSICode.reset)"

        if queueW >= 24 {
            let qRuleW = min(queueW - 2, 18)
            out += ANSICode.moveTo(row: sectionY + 1, col: queueX)
            out += "\(ANSICode.dim)\(String(repeating: "─", count: qRuleW))\(ANSICode.reset)"
        }

        // --- Cover art ---
        let hasArt = !artLines.isEmpty
        for i in 0..<artSize {
            if hasArt && i < artLines.count {
                out += ANSICode.moveTo(row: contentTopY + i, col: artX)
                out += "\(artLines[i])\(ANSICode.reset)"
            }
        }

        // --- Metadata ---
        let titleY = contentTopY
        let artistY = contentTopY + 1
        let albumY = contentTopY + 2
        let progressY = contentTopY + 4
        let outputY = contentTopY + 6
        let volumeY = contentTopY + 7

        // Title (boldest)
        out += ANSICode.moveTo(row: titleY, col: metaX)
        out += "\(ANSICode.bold)\(truncate(np.track, to: metaW))\(ANSICode.reset)"

        // Artist (strong secondary)
        out += ANSICode.moveTo(row: artistY, col: metaX)
        out += "\(ANSICode.bold)\(truncate(np.artist, to: metaW))\(ANSICode.reset)"

        // Album (dim)
        out += ANSICode.moveTo(row: albumY, col: metaX)
        out += "\(ANSICode.dim)\(truncate(np.album, to: metaW))\(ANSICode.reset)"

        // Progress bar: "0:00 ─────────●──────── 5:56"
        let elapsed = formatTime(np.position)
        let total = formatTime(np.duration)
        let timeW = elapsed.count + total.count + 2 // spaces
        let actualBarW = max(8, barW - timeW)
        let ratio = np.duration > 0 ? Double(np.position) / Double(np.duration) : 0
        let knobIdx = Int(ratio * Double(actualBarW - 1))

        var barStr = ""
        for i in 0..<actualBarW {
            if i == knobIdx {
                barStr += "\(ANSICode.bold)●\(ANSICode.reset)"
            } else if i < knobIdx {
                barStr += "\(ANSICode.dim)─\(ANSICode.reset)"
            } else {
                barStr += "\(ANSICode.dim)─\(ANSICode.reset)"
            }
        }

        out += ANSICode.moveTo(row: progressY, col: metaX)
        out += "\(elapsed) \(barStr) \(total)"

        // Output (speakers)
        let labelW = 8
        if !np.speakers.isEmpty {
            let mainSpeaker = np.speakers.first!
            out += ANSICode.moveTo(row: outputY, col: metaX)
            out += "\(ANSICode.dim)Output\(ANSICode.reset)"
            out += ANSICode.moveTo(row: outputY, col: metaX + labelW)
            out += truncate(mainSpeaker.name, to: metaW - labelW)

            out += ANSICode.moveTo(row: volumeY, col: metaX)
            out += "\(ANSICode.dim)Volume\(ANSICode.reset)"
            out += ANSICode.moveTo(row: volumeY, col: metaX + labelW)
            out += "\(mainSpeaker.volume)"

            // Additional speakers on next rows
            for (i, spk) in np.speakers.dropFirst().enumerated() {
                out += ANSICode.moveTo(row: volumeY + 1 + i, col: metaX + labelW)
                out += "\(ANSICode.dim)\(truncate(spk.name, to: metaW - labelW - 4)) \(spk.volume)\(ANSICode.reset)"
            }
        }

        // --- Queue ---
        if queueW >= 24 {
            let queueVisibleCount = min(8, termHeight - contentTopY - 4)
            for (i, entry) in trackList.prefix(queueVisibleCount).enumerated() {
                out += ANSICode.moveTo(row: contentTopY + i, col: queueX)
                let idx = String(format: "%02d", entry.index)
                let rowText = truncate("\(entry.name) — \(entry.artist)", to: queueW - 6)
                if entry.isCurrent {
                    out += "\(ANSICode.green)▶\(ANSICode.reset) \(ANSICode.bold)\(idx)  \(rowText)\(ANSICode.reset)"
                } else {
                    out += "\(ANSICode.dim)  \(idx)  \(rowText)\(ANSICode.reset)"
                }
            }
        }

        // --- Footer (docked, no border) ---
        out += ANSICode.moveTo(row: footerY, col: contentX)
        out += "\(ANSICode.dim)Controls\(ANSICode.reset)  "
        out += "\(ANSICode.bold)↑ ↓\(ANSICode.reset) Skip   "
        out += "\(ANSICode.bold)← →\(ANSICode.reset) Seek   "
        out += "\(ANSICode.bold)Space\(ANSICode.reset) Pause   "
        out += "\(ANSICode.bold)r\(ANSICode.reset) Radio   "
        out += "\(ANSICode.bold)q\(ANSICode.reset) Quit"

        print(out, terminator: "")
        fflush(stdout)
    }

    func renderStopped() {
        var out = ANSICode.cursorHome + ANSICode.clearScreen
        out += ANSICode.moveTo(row: contentY, col: contentX)
        out += "\(ANSICode.dim)\(ANSICode.bold)music\(ANSICode.reset)"
        out += ANSICode.moveTo(row: sectionY, col: artX)
        out += "\(ANSICode.cyan)Now Playing\(ANSICode.reset)"
        out += ANSICode.moveTo(row: sectionY + 1, col: artX)
        out += "\(ANSICode.dim)\(String(repeating: "─", count: 11))\(ANSICode.reset)"
        out += ANSICode.moveTo(row: contentTopY, col: artX)
        out += "\(ANSICode.dim)Nothing playing.\(ANSICode.reset)"
        out += ANSICode.moveTo(row: footerY, col: contentX)
        out += "\(ANSICode.dim)Controls\(ANSICode.reset)  \(ANSICode.bold)q\(ANSICode.reset) Quit"
        print(out, terminator: "")
        fflush(stdout)
    }

    func refreshTrackContext() {
        trackList = pollSurroundingTracks()
        if let artPath = extractArtwork() {
            artLines = artworkToAscii(path: artPath, width: artW, height: artSize)
        } else {
            artLines = []
        }
    }

    // Drain all pending input from stdin
    func flushStdin() {
        var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        while poll(&pfd, 1, 0) > 0 && pfd.revents & Int16(POLLIN) != 0 {
            var discard = [UInt8](repeating: 0, count: 256)
            _ = Darwin.read(STDIN_FILENO, &discard, 256)
        }
    }

    var lastSkipTime: UInt64 = 0
    func millisSinceEpoch() -> UInt64 {
        var tv = timeval()
        gettimeofday(&tv, nil)
        return UInt64(tv.tv_sec) * 1000 + UInt64(tv.tv_usec) / 1000
    }

    // Initial render
    let backend = AppleScriptBackend()
    if let np = pollNowPlaying() {
        lastTrackName = np.track
        refreshTrackContext()
        render(np)
    } else {
        renderStopped()
    }

    while true {
        let key = KeyPress.read(timeout: 1.0)

        if let key = key {
            switch key {
            case .up:
                _ = try? syncRun { try await backend.runMusic("previous track") }
            case .down:
                _ = try? syncRun { try await backend.runMusic("next track") }
            case .left:
                _ = try? syncRun {
                    try await backend.runMusic("set player position to (player position - 30)")
                }
            case .right:
                _ = try? syncRun {
                    try await backend.runMusic("set player position to (player position + 30)")
                }
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
            if np.track != lastTrackName {
                lastTrackName = np.track
                refreshTrackContext()
                // Drain all input that queued during the slow refresh
                flushStdin()
            }
            render(np)
        } else {
            renderStopped()
        }
    }
}
