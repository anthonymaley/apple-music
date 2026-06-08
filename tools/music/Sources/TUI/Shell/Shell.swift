// tools/music/Sources/TUI/Shell/Shell.swift
import Foundation

func runShell() {
    let backend = AppleScriptBackend()
    let store = NowPlayingStore()
    let appQueue = AppQueueStore()
    let poller = PlaybackPoller(store: store, backend: backend, appQueue: appQueue)
    let terminal = TerminalState.shared

    let router = Router(root: .nowPlaying)
    var scenes: [SceneID: Scene] = [.nowPlaying: NowPlayingScene(backend: backend, appQueue: appQueue)]
    let tabs: [(id: SceneID, title: String)] = [(.nowPlaying, "Now"), (.playlists, "Playlists"), (.speakers, "Speakers")]

    // Lazily build a scene the first time it's shown. Returns nil if it can't be
    // built (e.g. no playlists), so the caller can refuse the switch.
    func ensureScene(_ id: SceneID) -> Scene? {
        if let s = scenes[id] { return s }
        switch id {
        case .playlists:
            let names = fetchUserPlaylistNames(backend: backend)
            guard !names.isEmpty else { return nil }
            let scene = PlaylistsScene(backend: backend,
                                       playlists: names,
                                       sources: makePlaylistDataSources(backend: backend, names: names),
                                       appQueue: appQueue)
            scenes[id] = scene
            return scene
        case .speakers:
            let scene = SpeakersScene(backend: backend)
            scenes[id] = scene
            return scene
        default:
            return nil
        }
    }

    terminal.enterRawMode()
    print(ANSICode.cursorHome + ANSICode.clearScreen, terminator: "")
    poller.start()
    // Sweep temp queue playlists left by a prior session (sparing the one still
    // playing). Off-main so a slow Music doesn't delay first paint.
    DispatchQueue.global().async { sweepQueuePlaylists(backend: backend) }
    defer {
        poller.stop()
        terminal.exitRawMode()
    }

    func dims() -> (Int, Int) {
        let f = ScreenFrame.current()
        return (f.width, f.height)
    }

    while true {
        if terminalResized {
            terminalResized = false
            print(ANSICode.cursorHome + ANSICode.clearScreen, terminator: "")
            fflush(stdout)
        }

        let snap = store.read()
        let (w, h) = dims()
        let frame = shellLayout(width: w, height: h)
        guard let scene = ensureScene(router.active) ?? scenes[.nowPlaying] else { continue }
        scene.tick(snapshot: snap)

        var out = renderShellChrome(frame: frame)
        out += renderTabStrip(active: router.active, tabs: tabs, frame: frame)
        out += scene.render(frame: frame, snapshot: snap)
        // No persistent now-playing bar — playback (incl. live progress) lives on
        // the Now tab. Just the footer hint line at the bottom.
        out += ANSICode.moveTo(row: frame.footerY, col: 3) + ANSICode.clearLine
        out += "\(ANSICode.dim)1 Now  2 Playlists  3 Speakers  Tab Switch   \u{2191}\u{2193} Move  Enter Select  q Quit\(ANSICode.reset)"
        print(out, terminator: "")
        fflush(stdout)

        // 100ms tick: redraw on timeout so the Now tab's live progress advances.
        guard let key = KeyPress.read(timeout: 0.1) else { continue }

        // Raw-input scenes (filter/search) get every key, unmediated.
        if !shellShouldResolveGlobals(forSceneCapturing: scene.capturesAllInput) {
            switch scene.handle(key) {
            case .none, .redraw: break
            case .push(let id): router.push(id)
            case .pop: router.pop()
            case .quit: return
            }
            continue
        }

        // 1) Globals (work in every non-capturing scene).
        if let action = resolveGlobalKey(key) {
            switch action {
            case .playPause:  _ = try? syncRun { try await backend.runMusic("playpause") }
            case .volumeUp:   _ = try? syncRun { try await backend.runMusic("set sound volume to (sound volume + 5)") }
            case .volumeDown: _ = try? syncRun { try await backend.runMusic("set sound volume to (sound volume - 5)") }
            // next/prev drive the app-owned queue when one is active (the poller
            // can't rely on Music's queue post-26.x); otherwise Music's own controls.
            case .next:
                if let (pl, pos) = appQueue.step(1) { playQueueTrack(backend: backend, playlist: pl, position: pos) }
                else { _ = try? syncRun { try await backend.runMusic("next track") } }
            case .prev:
                if let (pl, pos) = appQueue.step(-1) { playQueueTrack(backend: backend, playlist: pl, position: pos) }
                else { _ = try? syncRun { try await backend.runMusic("previous track") } }
            case .shuffle:    shufflePlayCurrent(backend: backend, appQueue: appQueue)
            case .switchScene(let n):
                if n >= 1 && n <= tabs.count, ensureScene(tabs[n - 1].id) != nil { router.switchTo(tabs[n - 1].id) }
            case .quit:       return
            }
            continue
        }

        // 2) Tab cycles scenes.
        if case .char("\t") = key {
            if let idx = tabs.firstIndex(where: { $0.id == router.active }) {
                let nextId = tabs[(idx + 1) % tabs.count].id
                if ensureScene(nextId) != nil { router.switchTo(nextId) }
            }
            continue
        }

        // 3) Everything else (including Esc) goes to the scene; it decides whether
        //    Esc means an internal back (.redraw) or leaving the scene (.pop).
        switch scene.handle(key) {
        case .none, .redraw: break
        case .push(let id): router.push(id)
        case .pop: router.pop()
        case .quit: return
        }
    }
}
