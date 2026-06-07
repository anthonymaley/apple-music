// tools/music/Sources/TUI/Shell/NowPlayingScene.swift
import Foundation

final class NowPlayingScene: Scene {
    let id: SceneID = .nowPlaying
    let tabTitle = "Now"

    private let backend: AppleScriptBackend
    private var cursor = 0
    private var scroll = 0
    private var rows: [TrackListEntry] = []
    private var lastCurrentKey = ""

    init(backend: AppleScriptBackend) { self.backend = backend }

    func tick(snapshot: NowPlayingSnapshot) {
        rows = snapshot.surrounding
        // Snap the cursor to the current track when the track changes; leave it
        // alone otherwise so the user can browse Up Next.
        if case .active(let np) = snapshot.outcome {
            let key = trackKey(title: np.track, artist: np.artist)
            if key != lastCurrentKey {
                lastCurrentKey = key
                if let i = rows.firstIndex(where: { $0.isCurrent }) { cursor = i }
            }
        }
        if cursor >= rows.count { cursor = max(0, rows.count - 1) }
    }

    func render(frame: ShellFrame, snapshot: NowPlayingSnapshot) -> String {
        var out = ""
        for r in frame.bodyY..<(frame.bodyY + frame.bodyHeight) {
            out += ANSICode.moveTo(row: r, col: 1) + ANSICode.clearLine
        }
        guard frame.bodyHeight > 4, frame.width > 30 else { return out }

        guard case .active(let np) = snapshot.outcome else {
            out += ANSICode.moveTo(row: frame.bodyY + 1, col: 3) + "\(ANSICode.dim)Nothing playing.\(ANSICode.reset)"
            return out
        }

        // --- Hero: art (left) + metadata (right) ---
        let artLines = snapshot.artLines
        let artW = 26
        let artRows = min(artLines.count, max(0, frame.bodyHeight - 2))
        for i in 0..<artRows {
            out += ANSICode.moveTo(row: frame.bodyY + i, col: 3) + "\(artLines[i])\(ANSICode.reset)"
        }
        let hasArt = artRows > 0
        let metaX = hasArt ? 3 + artW + 2 : 3
        let metaW = max(10, frame.width - metaX - 2)
        var my = frame.bodyY
        let playIcon = np.state == "playing" ? "\u{25B6}" : "\u{23F8}"
        out += ANSICode.moveTo(row: my, col: metaX)
        out += "\(ANSICode.bold)\(ANSICode.brightWhite)\(playIcon) \(truncText(np.track, to: metaW - 2))\(ANSICode.reset)"
        my += 1
        out += ANSICode.moveTo(row: my, col: metaX) + truncText(np.artist, to: metaW)
        my += 1
        out += ANSICode.moveTo(row: my, col: metaX) + "\(ANSICode.dim)\(truncText(np.album, to: metaW))\(ANSICode.reset)"
        my += 2
        // Progress
        let elapsed = formatTime(np.position)
        let total = formatTime(np.duration)
        let ratio = np.duration > 0 ? Double(np.position) / Double(np.duration) : 0
        let pbW = min(28, max(8, metaW - 14))
        let knob = max(0, min(pbW - 1, Int(ratio * Double(pbW - 1))))
        var bar = ""
        for i in 0..<pbW { bar += i == knob ? "\(ANSICode.bold)\u{25CF}\(ANSICode.reset)" : "\(ANSICode.dim)\u{2500}\(ANSICode.reset)" }
        out += ANSICode.moveTo(row: my, col: metaX) + "\(elapsed) \(bar) \(total)"
        my += 2
        if !snapshot.contextName.isEmpty {
            out += ANSICode.moveTo(row: my, col: metaX) + "\(ANSICode.dim)from \(truncText(snapshot.contextName, to: metaW - 5))\(ANSICode.reset)"
        }

        // --- Up Next list, below the hero ---
        let listY = frame.bodyY + max(artRows, 8) + 1
        let listBottom = frame.bodyY + frame.bodyHeight - 1
        if listY + 1 <= listBottom {
            // Adapt context entries to the timeline-row shape the shared renderer expects.
            let timeline = rows.map { e in
                TimelineRow(
                    id: trackKey(title: e.name, artist: e.artist),
                    kind: .playlist, index: e.index,
                    title: e.name, artist: e.artist,
                    label: "\(e.name) \u{2014} \(e.artist)",
                    isCurrent: e.isCurrent, wasPlayed: false, isReplayable: true
                )
            }
            out += renderTimelineRows(
                rows: timeline,
                header: "Up Next",
                x: 3,
                y: listY,
                width: frame.width - 6,
                visibleHeight: listBottom - listY + 1,
                cursorIndex: cursor,
                scrollOffset: &scroll
            )
        }
        return out
    }

    func handle(_ key: KeyPress) -> SceneAction {
        switch key {
        case .up:
            guard !rows.isEmpty else { return .none }
            cursor = max(0, cursor - 1); return .redraw
        case .down:
            guard !rows.isEmpty else { return .none }
            cursor = min(max(0, rows.count - 1), cursor + 1); return .redraw
        case .enter:
            guard cursor < rows.count else { return .none }
            // Jump to the selected track within the current playlist by its real index.
            playTrackInCurrentPlaylist(backend: backend, index: rows[cursor].index)
            return .redraw
        case .left:
            _ = try? syncRun { try await self.backend.runMusic("set player position to (player position - 30)") }
            return .redraw
        case .right:
            _ = try? syncRun { try await self.backend.runMusic("set player position to (player position + 30)") }
            return .redraw
        default:
            return .none
        }
    }
}
