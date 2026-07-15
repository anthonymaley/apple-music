// The Radio tab: Favorites · Live · Personal, cycled with [ / ].
// Playback is the music:// scheme rewrite (StationPlayback). Favorites carry
// their own url+name so this tab paints and plays with NO network and NO token —
// Live/Personal/search degrade to an honest message instead.
import Foundation

final class RadioScene: Scene {
    let id: SceneID = .radio
    let tabTitle = "Radio"

    private var nav = RadioNav.initial
    private let store: StationStore
    private let catalog: RadioCatalog?
    private let opener: Opener

    private var live: [Station] = []
    private var personal: [Station] = []
    private var searchHits: [Station] = []
    private var loadAttempted = false

    // Raw text entry. `capturing` mirrors LibraryScene's filter capture; `adding`
    // is the `a` flow (URL or search term).
    private var capturing = false
    private var filter = ""
    private var adding = false
    private var addText = ""
    private var message: String?

    init(store: StationStore, catalog: RadioCatalog?, opener: Opener = SystemOpener()) {
        self.store = store
        self.catalog = catalog
        self.opener = opener
    }

    var capturesAllInput: Bool { capturing || adding }

    var footerHint: String {
        if adding { return "Enter Save/Search  Esc Cancel" }
        if capturing { return "type to filter  Enter Apply  Esc Clear" }
        return "[ ] View  Enter Play  f Favorite  a Add/Search  / Filter"
    }

    private var rows: [Station] {
        let base: [Station]
        switch nav.subView {
        case .favorites: base = store.favorites()
        case .live:      base = live
        case .personal:  base = personal
        }
        guard !filter.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var selection: Station? {
        let r = rows
        guard nav.cursor >= 0, nav.cursor < r.count else { return nil }
        return r[nav.cursor]
    }

    func handle(_ key: KeyPress) -> SceneAction {
        // Raw text entry FIRST — before vimAlias, or typed letters get eaten by
        // navigation (the 3.6.0 gotcha; see docs/playbook.md).
        if adding {
            switch key {
            case .enter:  commitAdd(); adding = false; addText = ""
            case .escape: adding = false; addText = ""; message = nil
            case .char(let c) where c == "\u{7F}" || c == "\u{8}":
                if !addText.isEmpty { addText.removeLast() }
            case .char(let c): addText.append(c)
            default: break
            }
            return .redraw
        }

        if capturing {
            switch key {
            case .enter:  capturing = false
            case .escape: capturing = false; filter = ""; nav.cursor = 0
            case .up:     nav.cursor = max(0, nav.cursor - 1)
            case .down:   nav.cursor = min(max(0, rows.count - 1), nav.cursor + 1)
            case .char(let c) where c == "\u{7F}" || c == "\u{8}":
                if !filter.isEmpty { filter.removeLast() }; nav.cursor = 0
            case .char(let c): filter.append(c); nav.cursor = 0
            default: break
            }
            return .redraw
        }

        let key = vimAlias(key, listScene: true)

        let rKey: RadioKey
        switch key {
        case .up:    rKey = .up
        case .down:  rKey = .down
        case .enter, .right: rKey = .enter
        case .char("["): rKey = .switchPrev
        case .char("]"): rKey = .switchNext
        case .char("f"): rKey = .toggleFav
        case .char("/"): capturing = true; return .redraw
        case .char("a"): adding = true; addText = ""; message = nil; return .redraw
        default: return .none
        }

        let (next, action) = radioReduce(nav, rKey, itemCount: rows.count, selection: selection)
        nav = next
        execute(action)
        return .redraw
    }

    private func execute(_ action: RadioAction) {
        switch action {
        case .none:
            break
        case .play(let s):
            do { try playStation(s, via: opener); message = "▶ \(s.name)" }
            catch { message = "✗ Couldn't start \(s.name)" }
        case .toggleFavorite(let s):
            do { try store.toggle(s) } catch { message = "✗ Couldn't save favorite" }
        }
    }

    /// One affordance, two inputs. URL detection is by SCHEME PREFIX only — not
    /// a heuristic. A bare "music.apple.com/..." is treated as a search term and
    /// simply finds nothing; that's predictable. Do not try to be clever here.
    private func commitAdd() {
        let input = addText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        let isURL = ["http://", "https://", "music://"].contains { input.hasPrefix($0) }
        if isURL {
            guard stationPlayURL(input) != nil, let p = parseStationURL(input) else {
                message = "✗ Not an Apple Music station URL"
                return
            }
            // Enrich if the API knows it; fall back to the slug if not. The API
            // is an optimization — BBC Radio 1 is unresolvable and must still work.
            let resolved = try? catalog?.resolve(id: p.id)
            let station = (resolved ?? nil) ?? Station(
                id: p.id, name: displayNameFromSlug(p.slug), url: input,
                isLive: nil, artworkURL: nil)
            do { try store.add(station); message = "★ \(station.name)" }
            catch { message = "✗ Couldn't save favorite" }
        } else {
            guard let catalog else { message = "✗ Search needs auth (music auth setup)"; return }
            do {
                searchHits = try catalog.search(term: input)
                message = searchHits.isEmpty
                    ? "No stations for \u{201C}\(input)\u{201D} — try pasting the station URL"
                    : "\(searchHits.count) result(s) — f to favorite"
            } catch {
                message = "✗ Search failed"
            }
        }
    }

    @discardableResult
    func tick(snapshot: NowPlayingSnapshot) -> Bool {
        // Live/Personal are fetched once, lazily, off the first tick after the
        // tab is entered. Favorites need no fetch — they're already on disk.
        guard let catalog, !loadAttempted else { return false }
        loadAttempted = true
        live = (try? catalog.liveStations()) ?? []
        personal = (try? catalog.personalStation()) ?? []
        return !(live.isEmpty && personal.isEmpty)
    }

    func render(frame: ShellFrame, snapshot: NowPlayingSnapshot) -> String {
        renderRadioBody(frame: frame, subView: nav.subView, rows: rows,
                        cursor: nav.cursor, filter: filter,
                        adding: adding, addText: addText, message: message)
    }
}

// TEMPORARY — replaced in the next task by the rail+hero renderer.
// A plain list is enough to prove keys, reducer, and tab wiring work.
func renderRadioBody(frame: ShellFrame, subView: RadioSubView, rows: [Station],
                     cursor: Int, filter: String, adding: Bool, addText: String,
                     message: String?) -> String {
    var out = ""
    var y = frame.bodyY
    let put: (String) -> Void = { line in
        out += "\u{1B}[\(y);1H\u{1B}[K" + String(line.prefix(frame.width))
        y += 1
    }
    put("  \(RadioSubView.allCases.map { $0 == subView ? "[\($0)]" : "\($0)" }.joined(separator: "  "))")
    if adding { put("  add> \(addText)") }
    else if !filter.isEmpty { put("  /\(filter)") }
    if let m = message { put("  \(m)") }
    for (i, s) in rows.enumerated() where y < frame.bodyY + frame.bodyHeight {
        put("\(i == cursor ? " ▸ " : "   ")\(s.name)\(s.isLive == true ? "  [LIVE]" : "")")
    }
    if rows.isEmpty { put("   (empty)") }
    return out
}
