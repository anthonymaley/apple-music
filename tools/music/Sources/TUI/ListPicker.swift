import Foundation
import Darwin

func runListPicker(
    title: String,
    items: [String],
    onPreview: ((Int) -> [String])? = nil
) -> Int? {
    let terminal = TerminalState.shared
    terminal.enterRawMode()
    defer { terminal.exitRawMode() }

    var cursor = 0

    // Terminal size
    func termSize() -> (rows: Int, cols: Int) {
        var ws = winsize()
        _ = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws)
        return (Int(ws.ws_row), Int(ws.ws_col))
    }

    let contentX = 3
    let titleY = 3
    let ruleY = 4
    let bodyY = 6

    func render() {
        let (termHeight, termCols) = termSize()
        let footerY = termHeight

        let useTwoPane = onPreview != nil && termCols >= 95

        var out = ANSICode.cursorHome + ANSICode.clearScreen

        // App label
        out += ANSICode.moveTo(row: 2, col: contentX)
        out += "\(ANSICode.dim)music\(ANSICode.reset)"

        // Title
        out += ANSICode.moveTo(row: titleY, col: contentX)
        out += "\(ANSICode.bold)\(ANSICode.cyan)♫ \(title)\(ANSICode.reset)"

        // Accent rule
        out += ANSICode.moveTo(row: ruleY, col: contentX)
        out += "\(ANSICode.dim)\(String(repeating: "─", count: min(40, title.count + 4)))\(ANSICode.reset)"

        // Column headers for two-pane mode
        let leftPaneWidth = useTwoPane ? Int(Double(termCols - contentX) * 0.4) : 0
        let rightPaneCol = contentX + leftPaneWidth + 2

        if useTwoPane {
            // Left column header
            out += ANSICode.moveTo(row: bodyY - 1, col: contentX)
            out += "\(ANSICode.bold)\(title)\(ANSICode.reset)"

            // Right column header
            out += ANSICode.moveTo(row: bodyY - 1, col: rightPaneCol)
            out += "\(ANSICode.bold)Preview\(ANSICode.reset)"

            // Underlines
            out += ANSICode.moveTo(row: bodyY, col: contentX)
            out += "\(ANSICode.dim)\(String(repeating: "─", count: min(leftPaneWidth, title.count + 2)))\(ANSICode.reset)"
            out += ANSICode.moveTo(row: bodyY, col: rightPaneCol)
            out += "\(ANSICode.dim)\(String(repeating: "─", count: 7))\(ANSICode.reset)"
        }

        // Visible items
        let listStartY = useTwoPane ? bodyY + 1 : bodyY
        let maxVisible = max(1, termHeight - listStartY - 2) // room for footer
        let start = max(0, min(cursor - maxVisible / 2, items.count - maxVisible))
        let end = min(items.count, start + maxVisible)

        for (offset, i) in (start..<end).enumerated() {
            let row = listStartY + offset
            out += ANSICode.moveTo(row: row, col: contentX)

            let pointer = i == cursor ? "\(ANSICode.cyan)▶\(ANSICode.reset)" : " "
            let label: String
            if useTwoPane {
                // Truncate to fit left pane
                let maxLen = leftPaneWidth - 4
                if items[i].count > maxLen {
                    label = String(items[i].prefix(maxLen - 1)) + "…"
                } else {
                    label = items[i]
                }
            } else {
                label = items[i]
            }
            out += "\(pointer) \(label)"
        }

        // Right pane — preview content
        if useTwoPane, let onPreview = onPreview {
            let previewLines = onPreview(cursor)
            let maxPreviewLines = max(1, termHeight - listStartY - 2)
            for (offset, line) in previewLines.prefix(maxPreviewLines).enumerated() {
                let row = listStartY + offset
                out += ANSICode.moveTo(row: row, col: rightPaneCol)
                // Truncate to fit
                let maxLen = termCols - rightPaneCol - 1
                if line.count > maxLen {
                    out += String(line.prefix(maxLen - 1)) + "…"
                } else {
                    out += line
                }
            }
        }

        // Footer — docked at bottom, no box
        out += ANSICode.moveTo(row: footerY, col: contentX)
        out += "\(ANSICode.dim)↑↓ Navigate   Enter Open   q Quit\(ANSICode.reset)"

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
