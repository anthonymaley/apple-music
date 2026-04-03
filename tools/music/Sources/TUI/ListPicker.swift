import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct PlaylistPreview {
    let name: String
    let trackCount: Int
    let tracks: [String]  // formatted as "Title — Artist"
}

func renderArtwork(path: String, width: Int, height: Int) -> [String] {
    guard let chafaPath = findExecutable("chafa") else { return [] }
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
    return []
}

// MARK: - Playlist browser action

enum PlaylistAction {
    case none
    case playTrack(playlistIndex: Int, trackIndex: Int)
    case playPlaylist(index: Int)
    case shufflePlaylist(index: Int)
}

// MARK: - Unified playlist browser

func runPlaylistBrowser(
    playlists: [String],
    onTracks: @escaping (Int) -> PlaylistPreview?,
    onArtwork: ((Int) -> String?)? = nil
) -> PlaylistAction {
    let terminal = TerminalState.shared
    terminal.enterRawMode()
    defer { terminal.exitRawMode() }

    enum Pane { case playlists, tracks }

    var focus: Pane = .playlists
    var plCursor = 0
    var plScroll = 0
    var trCursor = 0
    var trScroll = 0

    // Cache
    var previewCache: [Int: PlaylistPreview] = [:]
    var artCache: [Int: [String]] = [:]
    var lastLoadedPl = -1

    func loadPreview() {
        guard plCursor != lastLoadedPl else { return }
        lastLoadedPl = plCursor

        if previewCache[plCursor] == nil {
            previewCache[plCursor] = onTracks(plCursor)
        }
        // Artwork disabled in playlist browser — chafa conflicts with raw mode
        if artCache[plCursor] == nil {
            artCache[plCursor] = []
        }

        // Reset track cursor when playlist changes
        trCursor = 0
        trScroll = 0
    }

    let leftX = 3
    let leftW = 38
    let rightX = 48
    let thumbH = 12

    func render() {
        let frame = ScreenFrame.current()
        let rightW = frame.width - rightX - 2
        let maxPlVisible = max(1, frame.statusY - frame.bodyY - 4)
        let preview = previewCache[plCursor]
        let artLines = artCache[plCursor] ?? []

        let plFocused = focus == .playlists
        let statusText = "\(playlists.count) playlists"
        let footerText = "\(ANSICode.dim)Controls\(ANSICode.reset)  \(ANSICode.bold)↑↓\(ANSICode.reset) Move   \(ANSICode.bold)Tab\(ANSICode.reset) Switch pane   \(ANSICode.bold)Enter\(ANSICode.reset) Play   \(ANSICode.bold)p\(ANSICode.reset) Play all   \(ANSICode.bold)s\(ANSICode.reset) Shuffle   \(ANSICode.bold)q\(ANSICode.reset) Quit"

        var out = renderShell(title: "Playlists", status: statusText, footer: footerText)

        // --- Left pane: playlist list ---
        let listY = frame.bodyY + 2

        // Playlist scroll
        if plCursor < plScroll { plScroll = plCursor }
        if plCursor >= plScroll + maxPlVisible { plScroll = plCursor - maxPlVisible + 1 }

        let plEnd = min(playlists.count, plScroll + maxPlVisible)
        for i in plScroll..<plEnd {
            let row = listY + (i - plScroll)
            out += ANSICode.moveTo(row: row, col: leftX)
            let name = truncText(playlists[i], to: leftW - 4)
            if i == plCursor {
                let color = plFocused ? ANSICode.cyan : ANSICode.dim
                out += "\(color)▶\(ANSICode.reset) \(ANSICode.bold)\(name)\(ANSICode.reset)"
            } else {
                out += "  \(name)"
            }
        }

        // --- Right pane ---
        guard rightW > 10 else {
            print(out, terminator: "")
            fflush(stdout)
            return
        }

        var rightRow = frame.bodyY

        // Playlist title + count
        if let preview = preview {
            out += ANSICode.moveTo(row: rightRow, col: rightX)
            out += "\(ANSICode.bold)\(truncText(preview.name, to: rightW))\(ANSICode.reset)"
            rightRow += 1
            out += ANSICode.moveTo(row: rightRow, col: rightX)
            out += "\(ANSICode.dim)\(preview.trackCount) tracks\(ANSICode.reset)"
            rightRow += 2

            // Artwork
            for line in artLines {
                if rightRow >= frame.statusY - 2 { break }
                out += ANSICode.moveTo(row: rightRow, col: rightX)
                out += "\(line)\(ANSICode.reset)"
                rightRow += 1
            }
            if !artLines.isEmpty { rightRow += 1 }

            // Tracks header
            out += ANSICode.moveTo(row: rightRow, col: rightX)
            out += "\(ANSICode.bold)Tracks\(ANSICode.reset)"
            rightRow += 1
            out += ANSICode.moveTo(row: rightRow, col: rightX)
            out += "\(ANSICode.dim)\(String(repeating: "─", count: 10))\(ANSICode.reset)"
            rightRow += 1

            // Track list (scrollable)
            let trackStartY = rightRow
            let maxTrVisible = max(1, frame.statusY - trackStartY - 1)

            if trCursor < trScroll { trScroll = trCursor }
            if trCursor >= trScroll + maxTrVisible { trScroll = trCursor - maxTrVisible + 1 }

            let trEnd = min(preview.tracks.count, trScroll + maxTrVisible)
            let trFocused = focus == .tracks

            for i in trScroll..<trEnd {
                let row = trackStartY + (i - trScroll)
                out += ANSICode.moveTo(row: row, col: rightX)
                let idx = String(format: "%02d", i + 1)
                let trackText = truncText(preview.tracks[i], to: rightW - 6)

                if i == trCursor && trFocused {
                    out += "\(ANSICode.cyan)▶\(ANSICode.reset) \(ANSICode.bold)\(idx)  \(trackText)\(ANSICode.reset)"
                } else {
                    out += "\(ANSICode.dim)  \(idx)\(ANSICode.reset)  \(trackText)"
                }
            }

            // Track position indicator
            if preview.tracks.count > maxTrVisible {
                out += ANSICode.moveTo(row: frame.statusY, col: rightX)
                out += "\(ANSICode.dim)\(trCursor + 1)/\(preview.tracks.count) tracks\(ANSICode.reset)"
            }
        } else {
            out += ANSICode.moveTo(row: rightRow, col: rightX)
            out += "\(ANSICode.dim)Loading...\(ANSICode.reset)"
        }

        print(out, terminator: "")
        fflush(stdout)
    }

    // Show list immediately, load preview lazily
    var previewLoaded = false
    render()

    while true {
        let key = KeyPress.read(timeout: previewLoaded ? 60.0 : 0.1)

        // Load preview on first idle moment
        if !previewLoaded && key == nil {
            loadPreview()
            previewLoaded = true
            render()
            continue
        }

        guard let key = key else { continue }

        let trackCount = previewCache[plCursor]?.tracks.count ?? 0

        switch key {
        case .up:
            if focus == .playlists {
                plCursor = max(0, plCursor - 1)
                if previewCache[plCursor] != nil {
                    loadPreview()  // cached — instant
                } else {
                    lastLoadedPl = -1  // mark stale, load on next idle
                    previewLoaded = false
                }
            } else {
                trCursor = max(0, trCursor - 1)
            }

        case .down:
            if focus == .playlists {
                plCursor = min(playlists.count - 1, plCursor + 1)
                if previewCache[plCursor] != nil {
                    loadPreview()  // cached — instant
                } else {
                    lastLoadedPl = -1
                    previewLoaded = false
                }
            } else {
                trCursor = min(trackCount - 1, trCursor + 1)
            }

        case .char("\t"):  // Tab
            focus = (focus == .playlists) ? .tracks : .playlists

        case .enter:
            if focus == .playlists {
                focus = .tracks
                trCursor = 0
                trScroll = 0
            } else {
                return .playTrack(playlistIndex: plCursor, trackIndex: trCursor)
            }

        case .left, .escape:
            if focus == .tracks {
                focus = .playlists
            } else {
                return .none
            }

        case .char("p"):
            return .playPlaylist(index: plCursor)

        case .char("s"):
            return .shufflePlaylist(index: plCursor)

        case .char("q"):
            return .none

        default:
            break
        }

        render()
    }
}

// MARK: - Simple list picker (backward compat)

func runListPicker(
    title: String,
    items: [String],
    onPreview: ((Int) -> PlaylistPreview?)? = nil,
    onArtwork: ((Int) -> String?)? = nil
) -> Int? {
    let terminal = TerminalState.shared
    terminal.enterRawMode()
    defer { terminal.exitRawMode() }

    var cursor = 0
    var scrollOffset = 0

    func render() {
        let frame = ScreenFrame.current()
        let maxVisible = max(1, frame.statusY - frame.bodyY - 4)
        let statusText = "\(items.count) items"
        let footerText = "\(ANSICode.dim)Controls\(ANSICode.reset)  \(ANSICode.bold)↑↓\(ANSICode.reset) Navigate   \(ANSICode.bold)Enter\(ANSICode.reset) Select   \(ANSICode.bold)q\(ANSICode.reset) Quit"

        if cursor < scrollOffset { scrollOffset = cursor }
        if cursor >= scrollOffset + maxVisible { scrollOffset = cursor - maxVisible + 1 }

        var out = renderShell(title: title, status: statusText, footer: footerText)

        let listY = frame.bodyY + 2
        let end = min(items.count, scrollOffset + maxVisible)
        for i in scrollOffset..<end {
            let row = listY + (i - scrollOffset)
            out += ANSICode.moveTo(row: row, col: 3)
            if i == cursor {
                out += "\(ANSICode.cyan)▶\(ANSICode.reset) \(ANSICode.bold)\(truncText(items[i], to: frame.width - 8))\(ANSICode.reset)"
            } else {
                out += "  \(truncText(items[i], to: frame.width - 8))"
            }
        }

        print(out, terminator: "")
        fflush(stdout)
    }

    render()

    while true {
        guard let key = KeyPress.read() else { continue }
        switch key {
        case .up: cursor = max(0, cursor - 1)
        case .down: cursor = min(items.count - 1, cursor + 1)
        case .enter, .space: return cursor
        case .char("q"), .escape: return nil
        default: break
        }
        render()
    }
}
