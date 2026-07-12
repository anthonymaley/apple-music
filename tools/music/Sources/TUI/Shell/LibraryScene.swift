// tools/music/Sources/TUI/Shell/LibraryScene.swift
// The Library tab. Only the Albums sub-view is wired end to end (this task);
// Artists/Songs render an honest "coming soon" placeholder until later tasks.
// All navigation is delegated to the pure `libraryReduce`; the scene owns only
// view state (scroll, filter) and executes the emitted LibraryAction off-thread.
import Foundation

final class LibraryScene: Scene {
    let id: SceneID = .library
    let tabTitle = "Library"
    var capturesAllInput: Bool { capturing }
    var footerHint: String { "[ ] View  Enter Open  / Filter  p Play  s Shuffle" }

    private let backend: AppleScriptBackend
    private let sources: LibraryDataSources
    private let appQueue: AppQueueStore
    private let status: StatusStore
    private let actions: ActionRunner

    private var nav = LibraryNav.initial
    private var albums: [LibraryAlbum] = []
    private var albumsLoaded = false
    private var tracks: [String] = []
    private var tracksLoading = false
    private var filter = ""
    private var capturing = false
    private var railScroll = 0
    private var trackScroll = 0

    // Off-thread loads land here and are drained in tick() on the main thread,
    // so a slow REST/AppleScript round-trip never blocks a render frame
    // (mirrors SpeakersScene / PlaylistsScene).
    private let inboxLock = NSLock()
    private var albumsInbox: [LibraryAlbum]? = nil
    private var tracksInbox: [String]? = nil
    private let tracksQueue = DispatchQueue(label: "music.library.tracks")

    init(backend: AppleScriptBackend, sources: LibraryDataSources,
         appQueue: AppQueueStore, status: StatusStore, actions: ActionRunner) {
        self.backend = backend
        self.sources = sources
        self.appQueue = appQueue
        self.status = status
        self.actions = actions
        loadAlbums()
    }

    // MARK: background loads

    private func loadAlbums() {
        let sources = self.sources
        Thread.detachNewThread { [weak self] in
            let fetched = sources.onAlbums()
            guard let self else { return }
            self.inboxLock.lock()
            self.albumsInbox = fetched
            self.inboxLock.unlock()
        }
    }

    private func loadTracks(title: String, artist: String) {
        let sources = self.sources
        tracksQueue.async { [weak self] in
            let fetched = sources.onAlbumTracks(title, artist)
            guard let self else { return }
            self.inboxLock.lock()
            self.tracksInbox = fetched
            self.inboxLock.unlock()
        }
    }

    // MARK: Scene

    @discardableResult
    func tick(snapshot: NowPlayingSnapshot) -> Bool {
        var changed = false
        inboxLock.lock()
        let freshAlbums = albumsInbox; albumsInbox = nil
        let freshTracks = tracksInbox; tracksInbox = nil
        inboxLock.unlock()
        if let freshAlbums {
            albums = freshAlbums
            albumsLoaded = true
            if isAlbumList {
                let count = visibleAlbumIndices().count
                if nav.cursor >= count { nav.cursor = max(0, count - 1) }
            }
            changed = true
        }
        if let freshTracks {
            tracks = freshTracks
            tracksLoading = false
            if isTracksLevel, nav.cursor >= tracks.count { nav.cursor = max(0, tracks.count - 1) }
            changed = true
        }
        return changed
    }

    func render(frame: ShellFrame, snapshot: NowPlayingSnapshot) -> String {
        var out = ""
        for r in frame.bodyY..<(frame.bodyY + frame.bodyHeight) {
            out += ANSICode.moveTo(row: r, col: 1) + ANSICode.clearLine
        }
        let z = playlistZones(width: frame.width)
        let bodyTop = frame.bodyY
        let bodyBottom = frame.bodyY + frame.bodyHeight - 1

        // Sub-view header: Albums · Artists · Songs (active = cyan/bold).
        out += ANSICode.moveTo(row: bodyTop, col: z.railX) + subViewHeader()

        let contentTop = bodyTop + 2
        guard contentTop <= bodyBottom else { return out }

        // Only Albums is wired; the other tabs are visible but empty for now.
        guard nav.subView == .albums else {
            out += ANSICode.moveTo(row: contentTop, col: z.railX)
            out += "\(ANSICode.dim)\(subViewName(nav.subView)) — coming soon\(ANSICode.reset)"
            return out
        }

        renderRail(z, into: &out, contentTop: contentTop, bodyBottom: bodyBottom)
        renderHero(z, into: &out, contentTop: contentTop)
        renderRightPane(z, into: &out, contentTop: contentTop, bodyBottom: bodyBottom)

        if capturing || !filter.isEmpty {
            out += ANSICode.moveTo(row: bodyTop + 1, col: z.railX)
            out += "\(ANSICode.cyan)/\(ANSICode.reset) \(ANSICode.brightWhite)\(filter)\(ANSICode.reset)\(capturing ? "\u{2588}" : "")"
        }
        return out
    }

    func handle(_ key: KeyPress) -> SceneAction {
        // Raw filter entry (fzf-style: arrows move the filtered list while typing).
        if capturing {
            switch key {
            case .enter: capturing = false
            case .escape: capturing = false; filter = ""; clampAlbumCursor()
            case .up: nav.cursor = max(0, nav.cursor - 1)
            case .down: nav.cursor = min(max(0, visibleAlbumIndices().count - 1), nav.cursor + 1)
            case .char(let c) where c == "\u{7F}" || c == "\u{8}":
                if !filter.isEmpty { filter.removeLast() }; clampAlbumCursor()
            case .char(let c): filter.append(c); clampAlbumCursor()
            default: break
            }
            return .redraw
        }

        let libKey: LibraryKey
        switch key {
        case .up: libKey = .up
        case .down: libKey = .down
        case .enter: libKey = .enter
        case .left, .escape: libKey = .back
        case .char("["): libKey = .switchPrev
        case .char("]"): libKey = .switchNext
        case .char("p"), .char("P"): libKey = .play
        case .char("s"), .char("S"): libKey = .shuffle
        case .char("/"):
            if isAlbumList { capturing = true; return .redraw }
            return .none
        default:
            return .none
        }

        // Back at the root level leaves the tab (mirrors PlaylistsScene's left/esc).
        if libKey == .back && nav.stack.count == 1 { return .pop }

        let count = currentRowCount()
        let sel = selectionUnderCursor()
        let (newNav, action) = libraryReduce(nav, libKey, itemCount: count, selection: sel)
        let subViewChanged = newNav.subView != nav.subView
        let levelChanged = newNav.stack != nav.stack
        nav = newNav
        if subViewChanged { filter = "" }
        if subViewChanged || levelChanged { railScroll = 0; trackScroll = 0 }

        execute(action)
        switch action {
        case .play, .shuffle:
            return .push(.nowPlaying)   // jump to Now Playing on a play, like Playlists
        default:
            return .redraw
        }
    }

    // MARK: action execution

    private func execute(_ action: LibraryAction) {
        switch action {
        case .fetchAlbumTracks(_, let title, let artist):
            tracks = []
            tracksLoading = true
            loadTracks(title: title, artist: artist)
        case .play(.album(_, let title, let artist)):
            playAlbum(title: title, artist: artist, shuffle: false)
        case .shuffle(.album(_, let title, let artist)):
            playAlbum(title: title, artist: artist, shuffle: true)
        default:
            break   // song/artist actions wired in later tasks
        }
    }

    /// Whole-album play via Music's native (gapless) queue — relinquish the
    /// app-owned queue so the poller reads Music's context again. Two separate
    /// AppleScript calls (never batched, per the -50 rule); failures toast.
    private func playAlbum(title: String, artist: String, shuffle: Bool) {
        appQueue.clear()
        let escTitle = escapeAppleScriptString(title)
        let escArtist = escapeAppleScriptString(artist)
        let backend = self.backend
        actions.run("Play") {
            try require((try? syncRun { try await backend.runMusic("set shuffle enabled to \(shuffle)") }) != nil,
                        "Couldn't set shuffle for '\(title)'.")
            try require((try? syncRun { try await backend.runMusic("play (every track of playlist \"Library\" whose album is \"\(escTitle)\" and artist is \"\(escArtist)\")") }) != nil,
                        "Couldn't play '\(title)'.")
        }
    }

    // MARK: level helpers

    private var isAlbumList: Bool { if case .albumList = nav.current { return true }; return false }
    private var isTracksLevel: Bool { if case .tracks = nav.current { return true }; return false }

    private func currentRowCount() -> Int {
        switch nav.current {
        case .albumList: return visibleAlbumIndices().count
        case .tracks: return tracks.count
        default: return 0   // artists/songs later
        }
    }

    private func selectionUnderCursor() -> LibrarySelection? {
        switch nav.current {
        case .albumList:
            let vis = visibleAlbumIndices()
            guard nav.cursor >= 0, nav.cursor < vis.count else { return nil }
            let a = albums[vis[nav.cursor]]
            return LibrarySelection(id: a.id, primary: a.name, secondary: a.artist)
        case .tracks(let albumID, let albumTitle, let artist):
            // The reducer plays the album (from the level's stored identity) and
            // ignores the selection's contents at this level, but its Enter path
            // still guards on selection != nil — so hand back the album identity.
            return LibrarySelection(id: albumID, primary: albumTitle, secondary: artist)
        default:
            return nil   // artists/songs later
        }
    }

    private func visibleAlbumIndices() -> [Int] {
        guard !filter.isEmpty else { return Array(0..<albums.count) }
        let q = filter.lowercased()
        return (0..<albums.count).filter {
            "\(albums[$0].name) \(albums[$0].artist)".lowercased().contains(q)
        }
    }

    private func clampAlbumCursor() {
        let count = visibleAlbumIndices().count
        if nav.cursor >= count { nav.cursor = max(0, count - 1) }
        railScroll = 0
    }

    private func focusedAlbum() -> LibraryAlbum? {
        switch nav.current {
        case .albumList:
            let vis = visibleAlbumIndices()
            guard nav.cursor >= 0, nav.cursor < vis.count else { return nil }
            return albums[vis[nav.cursor]]
        case .tracks(let albumID, let albumTitle, let artist):
            return albums.first { $0.id == albumID } ?? LibraryAlbum(id: albumID, name: albumTitle, artist: artist)
        default:
            return nil
        }
    }

    // MARK: render helpers

    private func subViewName(_ sv: LibrarySubView) -> String {
        switch sv {
        case .albums: return "Albums"
        case .artists: return "Artists"
        case .songs: return "Songs"
        }
    }

    private func subViewHeader() -> String {
        LibrarySubView.allCases.map { sv -> String in
            let name = subViewName(sv)
            return sv == nav.subView
                ? "\(ANSICode.bold)\(ANSICode.cyan)\(name)\(ANSICode.reset)"
                : "\(ANSICode.dim)\(name)\(ANSICode.reset)"
        }.joined(separator: "\(ANSICode.dim)  \u{00B7}  \(ANSICode.reset)")
    }

    private func renderRail(_ z: PlaylistZones, into out: inout String, contentTop: Int, bodyBottom: Int) {
        let listY = contentTop
        let maxVisible = max(1, bodyBottom - listY + 1)
        let vis = visibleAlbumIndices()
        if vis.isEmpty {
            out += ANSICode.moveTo(row: listY, col: z.railX)
            let msg = albumsLoaded ? (filter.isEmpty ? "(no albums)" : "(no matches)") : "Loading albums\u{2026}"
            out += "\(ANSICode.dim)\(msg)\(ANSICode.reset)"
            return
        }
        // Which rail row is highlighted: the cursor at the album level, or the
        // drilled-into album while browsing its tracks.
        let atAlbumList = isAlbumList
        let cursorPos: Int
        if atAlbumList {
            cursorPos = min(max(0, nav.cursor), vis.count - 1)
        } else {
            cursorPos = drilledAlbumPos(in: vis) ?? 0
        }
        if cursorPos < railScroll { railScroll = cursorPos }
        if cursorPos >= railScroll + maxVisible { railScroll = cursorPos - maxVisible + 1 }
        let end = min(vis.count, railScroll + maxVisible)
        let nameWidth = max(1, z.railWidth - 2)
        for p in railScroll..<end {
            let i = vis[p]
            let row = listY + (p - railScroll)
            out += ANSICode.moveTo(row: row, col: z.railX)
            let a = albums[i]
            let label = "\(a.name) \u{2014} \(a.artist)"
            let nm = railName(label, nameWidth: nameWidth)
            let padName = nm + String(repeating: " ", count: max(0, nameWidth - nm.count))
            if p == cursorPos {
                if atAlbumList {
                    out += "\u{258C} \(ANSICode.inverse)\(padName)\(ANSICode.reset)"
                } else {
                    out += "\(ANSICode.dim)\u{258C}\(ANSICode.reset) \(ANSICode.brightWhite)\(padName)\(ANSICode.reset)"
                }
            } else {
                out += "  \(ANSICode.dim)\(padName)\(ANSICode.reset)"
            }
        }
    }

    private func drilledAlbumPos(in vis: [Int]) -> Int? {
        guard case .tracks(let albumID, _, _) = nav.current else { return nil }
        return vis.firstIndex { albums[$0].id == albumID }
    }

    private func renderHero(_ z: PlaylistZones, into out: inout String, contentTop: Int) {
        guard let a = focusedAlbum() else { return }
        var y = contentTop
        out += ANSICode.moveTo(row: y, col: z.heroX)
        out += "\(ANSICode.bold)\(ANSICode.brightWhite)\(truncText(a.name, to: z.heroWidth))\(ANSICode.reset)"
        y += 1
        out += ANSICode.moveTo(row: y, col: z.heroX)
        out += "\(ANSICode.dim)\(truncText(a.artist, to: z.heroWidth))\(ANSICode.reset)"
        y += 2

        let gw = min(28, z.heroWidth)
        let gh = 10
        let block = gradientBlock(name: a.name + a.artist, width: gw, height: gh)
        var seed = 0; for b in (a.name + a.artist).unicodeScalars { seed = (seed &* 31 &+ Int(b.value)) & 0xffffff }
        let r = 80 + (seed & 0x7f), g = 80 + ((seed >> 8) & 0x7f), bl = 80 + ((seed >> 16) & 0x7f)
        let color = "\u{1B}[38;2;\(r);\(g);\(bl)m"
        for line in block {
            out += ANSICode.moveTo(row: y, col: z.heroX) + "\(color)\(line)\(ANSICode.reset)"
            y += 1
        }
        y += 1

        if isTracksLevel {
            out += ANSICode.moveTo(row: y, col: z.heroX)
            let n = tracksLoading ? "\u{2026}" : "\(tracks.count)"
            out += "\(ANSICode.dim)\(n) tracks\(ANSICode.reset)"
            y += 2
        } else { y += 1 }

        out += ANSICode.moveTo(row: y, col: z.heroX)
        out += "\(ANSICode.lime)[Enter]\(ANSICode.reset) Open   \(ANSICode.lime)[P]\(ANSICode.reset) Play   \(ANSICode.lime)[S]\(ANSICode.reset) Shuffle   \(ANSICode.lime)[/]\(ANSICode.reset) Filter"
    }

    private func renderRightPane(_ z: PlaylistZones, into out: inout String, contentTop: Int, bodyBottom: Int) {
        guard z.mode == .three, let rx = z.rightX else { return }
        var y = contentTop
        guard isTracksLevel else {
            out += ANSICode.moveTo(row: y, col: rx) + "\(ANSICode.cyan)Tracks\(ANSICode.reset)"; y += 1
            out += ANSICode.moveTo(row: y, col: rx) + "\(ANSICode.dim)\(String(repeating: "\u{2500}", count: min(z.rightWidth, 18)))\(ANSICode.reset)"; y += 1
            out += ANSICode.moveTo(row: y, col: rx) + "\(ANSICode.dim)Enter to open an album\(ANSICode.reset)"
            return
        }
        out += ANSICode.moveTo(row: y, col: rx) + "\(ANSICode.cyan)Tracks\(ANSICode.reset) \(ANSICode.dim)\(tracks.count)\(ANSICode.reset)"; y += 1
        out += ANSICode.moveTo(row: y, col: rx) + "\(ANSICode.dim)\(String(repeating: "\u{2500}", count: min(z.rightWidth, 18)))\(ANSICode.reset)"; y += 1
        if tracks.isEmpty {
            out += ANSICode.moveTo(row: y, col: rx)
            out += "\(ANSICode.dim)\(tracksLoading ? "Loading\u{2026}" : "(empty)")\(ANSICode.reset)"
            return
        }
        let maxVis = max(1, bodyBottom - y + 1)
        let cur = min(max(0, nav.cursor), tracks.count - 1)
        if cur < trackScroll { trackScroll = cur }
        if cur >= trackScroll + maxVis { trackScroll = cur - maxVis + 1 }
        let end = min(tracks.count, trackScroll + maxVis)
        for i in trackScroll..<end {
            out += ANSICode.moveTo(row: y, col: rx)
            let idx = String(format: "%02d", i + 1)
            let text = truncText(tracks[i], to: max(2, z.rightWidth - 4))
            if i == cur {
                out += "\(ANSICode.inverse)\(idx)  \(text)\(ANSICode.reset)"
            } else {
                out += "\(ANSICode.dim)\(idx)\(ANSICode.reset)  \(text)"
            }
            y += 1
        }
    }
}
