// tools/music/Sources/TUI/Shell/ShellChrome.swift
import Foundation

/// App label + accent rule. Tab strip is rendered separately so it can be
/// hidden in the Bare tier.
func renderShellChrome(frame: ShellFrame) -> String {
    var out = ANSICode.cursorHome
    out += ANSICode.moveTo(row: frame.labelY, col: 3) + ANSICode.clearLine
    out += "\(ANSICode.dim)music\(ANSICode.reset)"
    out += ANSICode.moveTo(row: frame.ruleY, col: 3) + ANSICode.clearLine
    out += "\(ANSICode.dim)\(String(repeating: "\u{2500}", count: min(40, frame.width - 4)))\(ANSICode.reset)"
    return out
}

/// Horizontal scene tabs. `.full` shows names; `.digits` shows 1·2·3; `.hidden`
/// renders nothing. The active tab is highlighted in cyan/bold.
func renderTabStrip(active: SceneID, tabs: [(id: SceneID, title: String)], frame: ShellFrame) -> String {
    guard frame.tabStyle != .hidden, frame.tabsY > 0 else { return "" }
    var out = ANSICode.moveTo(row: frame.tabsY, col: 3) + ANSICode.clearLine
    out += "\(ANSICode.bold)\(ANSICode.cyan)\u{266B}\(ANSICode.reset)  "
    for (i, tab) in tabs.enumerated() {
        let isActive = tab.id == active
        let label: String
        switch frame.tabStyle {
        case .full:   label = tab.title
        case .digits: label = "\(i + 1)"
        case .hidden: label = ""
        }
        if isActive {
            out += "\(ANSICode.bold)\(ANSICode.cyan)\(label)\(ANSICode.reset)"
        } else {
            out += "\(ANSICode.dim)\(label)\(ANSICode.reset)"
        }
        if i < tabs.count - 1 { out += frame.tabStyle == .digits ? "\(ANSICode.dim)·\(ANSICode.reset)" : "   " }
    }
    return out
}

/// Persistent now-playing bar drawn in the bar band (frame.barY..) or, in the
/// Bare tier (barHeight 0), folded onto the footer row. Tier-aware: Full draws
/// three rows (track/artist+album, progress, speakers+modes); Compact/Minimal
/// draw one row; Bare draws a single status line.
func renderNowPlayingBar(snapshot: NowPlayingSnapshot, frame: ShellFrame) -> String {
    let col = 3
    let w = frame.width - col - 1

    // Resolve display fields from the snapshot.
    let np: NowPlayingState? = {
        if case .active(let s) = snapshot.outcome { return s }
        return nil
    }()

    // Clear the bar band (or the footer row in Bare tier).
    var out = ""
    let firstRow = frame.barHeight > 0 ? frame.barY : frame.footerY
    let rows = frame.barHeight > 0 ? frame.barHeight : 1
    for r in 0..<rows {
        out += ANSICode.moveTo(row: firstRow + r, col: 1) + ANSICode.clearLine
    }

    guard let np = np else {
        out += ANSICode.moveTo(row: firstRow, col: col)
        out += "\(ANSICode.dim)Nothing playing.\(ANSICode.reset)"
        return out
    }

    let playIcon = np.state == "playing" ? "\u{25B6}" : "\u{23F8}"
    let elapsed = formatTime(np.position)
    let total = formatTime(np.duration)
    let ratio = np.duration > 0 ? Double(np.position) / Double(np.duration) : 0

    func progress(_ width: Int) -> String {
        let knob = max(0, min(width - 1, Int(ratio * Double(width - 1))))
        var s = ""
        for i in 0..<width { s += i == knob ? "\(ANSICode.bold)\u{25CF}\(ANSICode.reset)" : "\(ANSICode.dim)\u{2500}\(ANSICode.reset)" }
        return s
    }

    switch frame.barTier {
    case .full:
        // Row 1: ▶ Track — Artist
        out += ANSICode.moveTo(row: frame.barY, col: col)
        out += "\(ANSICode.bold)\(playIcon) \(truncText(np.track, to: max(4, w / 2)))\(ANSICode.reset) \(ANSICode.dim)\u{2014}\(ANSICode.reset) \(truncText(np.artist, to: max(4, w / 3)))"
        // Row 2: Album · progress · time
        out += ANSICode.moveTo(row: frame.barY + 1, col: col)
        out += "\(ANSICode.dim)\(truncText(np.album, to: max(4, w / 3)))\(ANSICode.reset)  \(progress(min(24, max(8, w / 3))))  \(ANSICode.dim)\(elapsed) / \(total)\(ANSICode.reset)"
        // Row 3: speakers + modes
        out += ANSICode.moveTo(row: frame.barY + 2, col: col)
        let spk = np.speakers.isEmpty ? "" : np.speakers.map { "\($0.name) \($0.volume)" }.joined(separator: "  ")
        var modes = ""
        if np.shuffleEnabled { modes += "z\u{21C4} " }
        if np.repeatMode == "one" { modes += "r\u{21BB}1" } else if np.repeatMode == "all" { modes += "r\u{21BB}" }
        out += "\(ANSICode.dim)\u{266A} \(truncText(spk, to: max(4, w - modes.count - 4)))   \(modes)\(ANSICode.reset)"

    case .compact, .minimal:
        out += ANSICode.moveTo(row: frame.barY, col: col)
        out += "\(ANSICode.bold)\(playIcon)\(ANSICode.reset) \(truncText("\(np.track) \u{2014} \(np.artist)", to: max(8, w - 22)))  \(progress(min(12, max(6, w / 6))))  \(ANSICode.dim)\(elapsed)/\(total)\(ANSICode.reset)"

    case .bare:
        out += ANSICode.moveTo(row: frame.footerY, col: col)
        out += "\(playIcon) \(truncText("\(np.track) \u{2014} \(np.artist)", to: max(8, w - 12)))  \(ANSICode.dim)\(elapsed)/\(total)\(ANSICode.reset)"
    }

    return out
}
