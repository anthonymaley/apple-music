// tools/music/Sources/TUI/Shell/NowPlayingScene.swift
import Foundation

enum ContinuationAction: Equatable { case shuffle, playlist, quiet }

func continuationAction(for key: KeyPress) -> ContinuationAction? {
    switch key {
    case .char("s"), .char("S"): return .shuffle
    case .char("p"), .char("P"): return .playlist
    case .char("q"), .char("Q"): return .quiet
    default: return nil
    }
}

final class NowPlayingScene: Scene {
    let id: SceneID = .nowPlaying
    let tabTitle = "Now"
    var footerHint: String { "\u{2191}\u{2193} Browse  Enter Jump  \u{2190}\u{2192} Seek  n Next\u{2011}up" }

    private let backend: AppleScriptBackend
    private let appQueue: AppQueueStore
    private var cursor = 0
    private var scroll = 0
    private var rows: [TrackListEntry] = []
    private var lastCurrentKey = ""
    private var manualMenu = false   // user-opened menu (vs poller-detected queueEnded)
    private var menuShownLastFrame = false
    private var pendingSeedTitle = ""
    private var pendingSeedArtist = ""
    private var pendingPlaylist = ""         // context/ended playlist, for the Shuffle action
    private var pendingFromStopped = false   // menu opened from an auto queue-end (playback stopped)
    private var wantsPlaylists = false

    init(backend: AppleScriptBackend, appQueue: AppQueueStore) {
        self.backend = backend
        self.appQueue = appQueue
    }

    // Once the user acts on an auto-detected queue-end, remember which one (by its
    // ended track) so the menu doesn't re-appear for the same event — e.g. after
    // picking Quiet, which leaves playback stopped with queueEnded still set.
    private var dismissedSeed = ""
    private func menuActive(_ snapshot: NowPlayingSnapshot) -> Bool {
        (snapshot.queueEnded && snapshot.endedTrack != dismissedSeed) || manualMenu
    }
    var capturesAllInput: Bool { menuShownLastFrame }

    @discardableResult
    func tick(snapshot: NowPlayingSnapshot) -> Bool {
        menuShownLastFrame = menuActive(snapshot)
        pendingFromStopped = snapshot.queueEnded
        if snapshot.queueEnded {
            pendingSeedTitle = snapshot.endedTrack
            pendingSeedArtist = snapshot.endedArtist
            pendingPlaylist = snapshot.endedPlaylist
        } else if case .active(let np) = snapshot.outcome {
            pendingSeedTitle = np.track
            pendingSeedArtist = np.artist
            pendingPlaylist = cleanContextName(snapshot.contextName)
        }
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
        // Everything above is a pure function of the snapshot; the store's
        // generation counter already triggers the repaint when it changes.
        return false
    }

    func render(frame: ShellFrame, snapshot: NowPlayingSnapshot) -> String {
        var out = ""
        for r in frame.bodyY..<(frame.bodyY + frame.bodyHeight) {
            out += ANSICode.moveTo(row: r, col: 1) + ANSICode.clearLine
        }
        guard frame.bodyHeight > 4, frame.width > 30 else { return out }

        if menuActive(snapshot) {
            return renderContinuationMenu(frame: frame, snapshot: snapshot, into: out)
        }

        guard case .active(let np) = snapshot.outcome else {
            out += ANSICode.moveTo(row: frame.bodyY + 1, col: 3) + "\(ANSICode.dim)Nothing playing.\(ANSICode.reset)"
            return out
        }

        // Two-pane when wide enough: left = now-playing (large art + metadata),
        // right = Up Next list. Narrow falls back to stacked (art+meta, list below).
        let twoPane = frame.width >= 92
        let leftX = 3
        let leftW = twoPane ? 44 : (frame.width - 6)
        let listBottom = frame.bodyY + frame.bodyHeight - 1

        // --- Left pane: large album art ---
        let artLines = snapshot.artLines
        let artRows = min(artLines.count, max(0, frame.bodyHeight - 7))
        for i in 0..<artRows {
            out += ANSICode.moveTo(row: frame.bodyY + i, col: leftX) + "\(artLines[i])\(ANSICode.reset)"
        }

        // --- Left pane: metadata below the art ---
        var my = frame.bodyY + artRows + 1
        let metaW = leftW
        let playIcon = np.state == "playing" ? "\u{25B6}" : "\u{23F8}"
        out += ANSICode.moveTo(row: my, col: leftX)
        out += "\(ANSICode.bold)\(ANSICode.brightWhite)\(playIcon) \(truncText(np.track, to: metaW - 2))\(ANSICode.reset)"
        my += 1
        out += ANSICode.moveTo(row: my, col: leftX) + truncText(np.artist, to: metaW)
        my += 1
        out += ANSICode.moveTo(row: my, col: leftX) + "\(ANSICode.dim)\(truncText(np.album, to: metaW))\(ANSICode.reset)"
        my += 2
        let elapsed = formatTime(np.position)
        let total = formatTime(np.duration)
        let ratio = np.duration > 0 ? Double(np.position) / Double(np.duration) : 0
        let pbW = min(28, max(8, metaW - 14))
        let knob = max(0, min(pbW - 1, Int(ratio * Double(pbW - 1))))
        var bar = ""
        for i in 0..<pbW { bar += i == knob ? "\(ANSICode.bold)\u{25CF}\(ANSICode.reset)" : "\(ANSICode.dim)\u{2500}\(ANSICode.reset)" }
        out += ANSICode.moveTo(row: my, col: leftX) + "\(elapsed) \(bar) \(total)"
        my += 2
        if !snapshot.contextName.isEmpty {
            out += ANSICode.moveTo(row: my, col: leftX) + "\(ANSICode.cyan)\u{266A} \(ANSICode.reset)\(ANSICode.brightWhite)\(truncText(cleanContextName(snapshot.contextName), to: metaW - 3))\(ANSICode.reset)"
        }

        // --- Up Next: right pane (wide) or below the metadata (narrow) ---
        let listX = twoPane ? (leftX + leftW + 2) : leftX
        let listY = twoPane ? frame.bodyY : (my + 2)
        let listW = twoPane ? max(20, frame.width - listX - 1) : (frame.width - 6)
        if listY + 1 <= listBottom {
            // Adapt context entries to the timeline-row shape the shared renderer expects.
            let timeline = rows.map { e in
                TimelineRow(
                    index: e.index,
                    label: "\(e.name) \u{2014} \(e.artist)",
                    isCurrent: e.isCurrent, wasPlayed: false
                )
            }
            out += renderTimelineRows(
                rows: timeline,
                header: "Up Next",
                x: listX,
                y: listY,
                width: listW,
                visibleHeight: listBottom - listY + 1,
                cursorIndex: cursor,
                scrollOffset: &scroll
            )
        }
        return out
    }

    private func renderContinuationMenu(frame: ShellFrame, snapshot: NowPlayingSnapshot, into base: String) -> String {
        var out = base
        let (seedTitle, art): (String, [String]) = snapshot.queueEnded
            ? (snapshot.endedTrack, snapshot.endedArtLines)
            : ({ if case .active(let np) = snapshot.outcome { return np.track } else { return "" } }(), snapshot.artLines)
        let title = snapshot.queueEnded
            ? "Queue ended — what next?"
            : "What next?"
        out += ANSICode.moveTo(row: frame.bodyY, col: 3)
        out += "\(ANSICode.bold)\(ANSICode.cyan)\(title)\(ANSICode.reset)"

        // Art thumbnail (shared by Radio/Similar cards), then a labelled option list.
        let artTop = frame.bodyY + 2
        let artRows = min(art.count, max(0, frame.bodyHeight - 8))
        for i in 0..<artRows {
            out += ANSICode.moveTo(row: artTop + i, col: 3) + "\(art[i])\(ANSICode.reset)"
        }
        let lx = 3
        var ly = artTop + artRows + 1
        let shuffleTarget = pendingPlaylist.isEmpty ? seedTitle : pendingPlaylist
        let opts: [(String, String)] = [
            ("[S]", "Shuffle  \(ANSICode.dim)\(truncText(shuffleTarget, to: 28))\(ANSICode.reset)"),
            ("[P]", "Playlist  \(ANSICode.dim)browse\(ANSICode.reset)"),
            ("[Q]", "Quiet  \(ANSICode.dim)stop here\(ANSICode.reset)"),
        ]
        for (key, label) in opts {
            out += ANSICode.moveTo(row: ly, col: lx) + "\(ANSICode.lime)\(key)\(ANSICode.reset)  \(label)"
            ly += 1
        }
        return out
    }

    private func act(on action: ContinuationAction) {
        switch action {
        case .shuffle:
            // Replay the just-played playlist shuffled, via the app-owned queue.
            // Falls back to shuffling whatever's playing if there's no playlist name.
            if !pendingPlaylist.isEmpty {
                shufflePlayPlaylist(backend: backend, appQueue: appQueue, playlist: pendingPlaylist)
            } else {
                shufflePlayCurrent(backend: backend, appQueue: appQueue)
            }
        case .playlist:
            wantsPlaylists = true
        case .quiet:
            appQueue.clear()
            _ = try? syncRun { try await self.backend.runMusic("pause") }
        }
    }

    func handle(_ key: KeyPress) -> SceneAction {
        // Continuation menu intercepts its keys when active.
        if menuShownLastFrame {
            if let action = continuationAction(for: key) {
                act(on: action)
                manualMenu = false
                dismissedSeed = pendingSeedTitle   // don't re-show this queue-end's menu
                if wantsPlaylists { wantsPlaylists = false; return .push(.playlists) }
                return .redraw
            }
            // any other key dismisses the manual menu (auto menu stays until poller clears it)
            if case .escape = key { manualMenu = false; return .redraw }
        }
        // Manual open: 'n' (next-options) when no menu is up.
        if case .char("n") = key, !menuShownLastFrame {
            manualMenu = true; return .redraw
        }
        switch key {
        case .up:
            guard !rows.isEmpty else { return .none }
            cursor = max(0, cursor - 1); return .redraw
        case .down:
            guard !rows.isEmpty else { return .none }
            cursor = min(max(0, rows.count - 1), cursor + 1); return .redraw
        case .enter:
            guard cursor < rows.count else { return .none }
            // Jump within the app-owned queue by the row's play-order position. For
            // album/library contexts (no app queue), play the row by title/artist —
            // `play track N of current playlist` is regressed on macOS 26.x (drops
            // context to the library), so use the same library lookup the poller's
            // auto-advance relies on. Duplicate titles resolve to the first match,
            // the limitation the poller already accepts.
            if let (pl, pos) = appQueue.jump(to: rows[cursor].index) {
                playQueueTrack(backend: backend, playlist: pl, position: pos)
            } else {
                playLibraryTrack(backend: backend, title: rows[cursor].name, artist: rows[cursor].artist)
            }
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
