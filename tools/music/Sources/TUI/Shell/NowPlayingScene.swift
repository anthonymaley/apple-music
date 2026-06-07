// tools/music/Sources/TUI/Shell/NowPlayingScene.swift
import Foundation

final class NowPlayingScene: Scene {
    let id: SceneID = .nowPlaying
    let tabTitle = "Now"

    private let backend: AppleScriptBackend
    private var cursor = 0
    private var scroll = 0
    private var rows: [TimelineRow] = []

    init(backend: AppleScriptBackend) { self.backend = backend }

    func tick(snapshot: NowPlayingSnapshot) {
        rows = buildStandaloneRows(history: snapshot.history, surrounding: snapshot.surrounding)
        if cursor >= rows.count { cursor = max(0, rows.count - 1) }
    }

    func render(frame: ShellFrame, snapshot: NowPlayingSnapshot) -> String {
        // Clear the body region first (prevents stale rows on shrink).
        var out = ""
        for r in frame.bodyY..<(frame.bodyY + frame.bodyHeight) {
            out += ANSICode.moveTo(row: r, col: 1) + ANSICode.clearLine
        }
        guard frame.bodyHeight > 3, frame.width > 30 else { return out }
        out += renderTimelineRows(
            rows: rows,
            header: "Album",
            x: 3,
            y: frame.bodyY,
            width: frame.width - 6,
            visibleHeight: frame.bodyHeight,
            cursorIndex: cursor,
            scrollOffset: &scroll
        )
        return out
    }

    func handle(_ key: KeyPress) -> SceneAction {
        switch key {
        case .up:
            guard !rows.isEmpty else { return .none }
            cursor = max(0, cursor - 1)
            return .redraw
        case .down:
            guard !rows.isEmpty else { return .none }
            cursor = min(max(0, rows.count - 1), cursor + 1)
            return .redraw
        case .enter:
            guard cursor < rows.count else { return .none }
            let row = rows[cursor]
            playLibraryTrack(backend: backend, title: row.title, artist: row.artist)
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
