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
    var lastPreviewCursor = -1
    var cachedPreview: PlaylistPreview? = nil
    var cachedArtLines: [String] = []

    let leftX = 3
    let leftW = 42
    let rightX = 52

    func refreshPreview() {
        guard cursor != lastPreviewCursor else { return }
        lastPreviewCursor = cursor
        cachedPreview = onPreview?(cursor)
        cachedArtLines = []
        if let onArtwork = onArtwork, let artPath = onArtwork(cursor) {
            cachedArtLines = renderArtwork(path: artPath, width: 14, height: 14)
        }
    }

    func render() {
        let frame = ScreenFrame.current()
        let maxVisible = max(1, frame.statusY - frame.bodyY - 4)
        let useTwoPane = onPreview != nil && frame.width >= 95

        // Scrolling
        if cursor < scrollOffset {
            scrollOffset = cursor
        } else if cursor >= scrollOffset + maxVisible {
            scrollOffset = cursor - maxVisible + 1
        }

        // Status and footer
        let statusText = "\(items.count) \(items.count == 1 ? "playlist" : "playlists")"
        let footerText = "\(ANSICode.dim)Controls\(ANSICode.reset)  ↑↓ Navigate   Enter Open   p Play   q Quit"

        var out = renderShell(title: title, status: statusText, footer: footerText)

        if useTwoPane {
            // --- Left pane: playlist list ---
            let listY = frame.bodyY + 2
            let end = min(items.count, scrollOffset + maxVisible)
            let maxLen = leftW - 4

            for i in scrollOffset..<end {
                let row = listY + (i - scrollOffset)
                out += ANSICode.moveTo(row: row, col: leftX)

                let truncated = truncText(items[i], to: maxLen)

                if i == cursor {
                    out += "\(ANSICode.cyan)▶\(ANSICode.reset) \(ANSICode.bold)\(truncated)\(ANSICode.reset)"
                } else {
                    out += "  \(truncated)"
                }
            }

            // --- Right pane ---
            let rightW = frame.width - rightX - 2

            if rightW > 10 {
                // Preview header + rule
                out += ANSICode.moveTo(row: frame.bodyY, col: rightX)
                out += "\(ANSICode.bold)Preview\(ANSICode.reset)"
                out += ANSICode.moveTo(row: frame.bodyY + 1, col: rightX)
                out += "\(ANSICode.dim)\(String(repeating: "─", count: min(7, rightW)))\(ANSICode.reset)"

                if let preview = cachedPreview {
                    // Playlist name (bold)
                    out += ANSICode.moveTo(row: frame.bodyY + 3, col: rightX)
                    out += "\(ANSICode.bold)\(truncText(preview.name, to: rightW))\(ANSICode.reset)"

                    // Track count (dim)
                    out += ANSICode.moveTo(row: frame.bodyY + 5, col: rightX)
                    out += "\(ANSICode.dim)\(preview.trackCount) tracks\(ANSICode.reset)"

                    // Artwork
                    var artEndY = frame.bodyY + 8
                    for (idx, line) in cachedArtLines.enumerated() {
                        let artRow = frame.bodyY + 8 + idx
                        if artRow >= frame.statusY - 1 { break }
                        out += ANSICode.moveTo(row: artRow, col: rightX)
                        out += "\(line)\(ANSICode.reset)"
                        artEndY = artRow + 1
                    }
                    if !cachedArtLines.isEmpty { artEndY += 1 }

                    // Track list below artwork
                    let maxTrackRows = max(0, frame.statusY - 1 - artEndY)
                    for (idx, track) in preview.tracks.prefix(maxTrackRows).enumerated() {
                        out += ANSICode.moveTo(row: artEndY + idx, col: rightX)
                        let num = "\(ANSICode.dim)\(idx + 1).\(ANSICode.reset) "
                        out += num + truncText(track, to: rightW - 5)
                    }
                }
            }
        } else {
            // --- Single-pane layout ---
            let listY = frame.bodyY + 2
            let end = min(items.count, scrollOffset + maxVisible)

            for i in scrollOffset..<end {
                let row = listY + (i - scrollOffset)
                out += ANSICode.moveTo(row: row, col: leftX)

                if i == cursor {
                    out += "\(ANSICode.cyan)▶\(ANSICode.reset) \(ANSICode.bold)\(truncText(items[i], to: frame.width - 8))\(ANSICode.reset)"
                } else {
                    out += "  \(truncText(items[i], to: frame.width - 8))"
                }
            }
        }

        print(out, terminator: "")
        fflush(stdout)
    }

    // Initial render without preview (show list immediately)
    render()

    // Load first preview after initial render is visible
    refreshPreview()
    render()

    while true {
        guard let key = KeyPress.read() else { continue }
        switch key {
        case .up:
            cursor = max(0, cursor - 1)
        case .down:
            cursor = min(items.count - 1, cursor + 1)
        case .enter, .space, .char("p"):
            return cursor
        case .char("q"), .escape:
            return nil
        default:
            break
        }
        refreshPreview()
        render()
    }
}
