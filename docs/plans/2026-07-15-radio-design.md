# Radio — design spec (2026-07-15)

A Radio tab: favorite stations, the live radio lineup, your personal station, and
two ways to add more. Playback rides the `music://` scheme rewrite probed and
audio-verified on 2026-07-15.

Status: **design approved, not built.** Findings live in `CONTEXT.md` → Key
Decisions → Radio and `docs/playbook.md`.

## Why this exists

Radio is the only feature the Cider-dependent `apple-music-tui` has that MusicTUI
lacks — and per the 2026-07-14 SEO audit, that project is what the AI answer box
crowns for "apple music tui". Every *native* competitor has no radio at all.
`music://` closes that gap natively, keeping AirPlay groups, with no second app in
the chain.

## What the probe established (all live-verified 2026-07-15)

| Fact | Evidence |
|---|---|
| A station plays via `open "music://…"` — the station's REST `url` with `https://`→`music://` | audio confirmed by the user |
| The AirPlay route **survives** | MacBook Pro + Kitchen held across every probe |
| No AppleScript, no Accessibility, no MusicKit | — |
| `https://` on the same URL opens **Safari** | the scheme rewrite is the whole trick |
| Track-based stations (`isLive=false`, incl. personal) have a **full track model** | name/artist/album, `duration=237.0`, position advances |
| Transport works on track-based stations | `skip`→"Up All Night — Beck"; pause; resume |
| Live stations have **no track model** | `duration = missing value`, `position = 0.0` |
| Live stations **break `music now`** → break `statusline.sh` | `jq: parse error: Invalid numeric literal` |
| Live-station metadata **varies** | Apple Music 1 reports the song; BBC Radio 1 reports the station name, empty artist |
| Third-party live stations play | BBC Radio 1 |

### Hard constraints discovered

- **No browse-all.** Unfiltered `GET /v1/catalog/{sf}/stations` → `400`. Only
  `ids=`, `filter[featured]=apple-music-live-radio` (6 stations), or
  `filter[identity]=personal` (1).
- **Genres cannot be built.** A `station-genre` is `{"name": "Jazz"}` — no
  relationships, no views. `stations?filter[genre]=` → `400`. Station objects
  carry no genre field. There is no path from a genre to its stations in either
  direction.
- **Search is shallow and unreliable.** `types=stations` returns 5–7 hits, no
  pagination. Searching "bbc radio 1" returns Mozart and Beethoven stations.
- **The catalog API does not cover everything playable.** BBC Radio 1
  (`ra.1460912634`) plays fine but returns `data: []` by id — in `us`, `gb`, and
  `be`, with and without a user token. **Why is unknown.** Do not build anything
  that assumes the API can resolve an arbitrary station URL.
- Catalog station endpoints need **only a developer token** (live 200 with no
  Music-User-Token).

## Scope

**In:** a Radio tab (Favorites · Live · Personal), favorites persisted locally,
add-by-URL and add-by-search, `music radio` CLI verbs, the `music now`
live-station fix, and the `__radio__` dead-code sweep.

**Out:**
- **Seeded "station from this song"** — still Accessibility-walled; re-confirmed
  2026-07-15. This is what 1.11.0 removed; it is *not* what this ships.
- **Genre browse** — cannot be built (see above).
- **Station artwork in the Now-tab hero** — separate concern.

## Architecture

The mechanism is one pure function plus a seam:

```swift
// Sources/TUI/StationPlayback.swift

/// https://music.apple.com/us/station/<slug>/<id>  ->  music://…
/// Returns nil unless host is music.apple.com AND the path is a /station/ path —
/// otherwise a pasted album URL would silently play an album.
func stationPlayURL(_ shareURL: String) -> String?

protocol Opener { func open(_ url: String) throws }   // seam: tests never launch Music
func playStation(_ s: Station, via: Opener) throws
```

Three components, one job each:

| Unit | Owns | Depends on |
|---|---|---|
| `StationStore` | favorites: load/save `~/.config/music/stations.json`, add/remove/dedupe | pure + file I/O |
| `RadioCatalog` | REST reads: featured live, personal, search, by-id | dev token, injected fetch |
| `RadioScene` | the tab: subviews, rail, hero, keys | the two above |

### Data model

```swift
struct Station: Codable, Equatable {
    let id: String          // ra.978194965
    let name: String
    let url: String         // the https:// share URL — the play handle
    let isLive: Bool?       // nil = unknown; observed at play time
    let artworkURL: String?
}
```

`url` is stored, not just `id` — a favorite must keep working when the API can't
resolve it (the BBC Radio 1 case). `isLive` is `Optional` because it is genuinely
unknown for unresolvable stations and is **observed at play time**
(`duration == missing value` ⇒ live). The API is an optimization, never a
dependency.

Favorites file: `~/.config/music/stations.json` — same neighbourhood and pattern
as `artist-tiers.json`, `last-speakers.json`, `playlist-meta.json` (cached, seeded
on launch for an instant paint, no network on tab entry).

### Why local favorites, not Apple's library

Apple's own mechanism exists — a station added to the library becomes a
`URL track` (Apple Music 1 is already in this library that way). Rejected: that
track's `name` is **`ra.978194965`**, not "Apple Music 1", so leaning on it would
litter the ~14k Songs list with `ra.xxxxx` rows. Sync value is low — the phone
already has Apple's own Radio tab. Local storage also keeps unresolvable stations
(BBC Radio 1) first-class.

## UX

`RadioNav` mirrors `LibraryNav` minus the drill stack — stations are flat.

```swift
enum RadioSubView: CaseIterable, Equatable { case favorites, live, personal }
enum RadioKey { case up, down, enter, switchNext, switchPrev, toggleFav, add }
struct RadioNav: Equatable { var subView: RadioSubView; var cursor: Int }
```

| Key | Action | Precedent |
|---|---|---|
| `j/k` `↑/↓` | navigate | `vimAlias(key, listScene: true)` |
| `Enter` / `→` | play | Library drill-in |
| `[` `]` | cycle Favorites · Live · Personal | Library `switchPrev/switchNext` |
| `/` | local filter over the current list | Library fzf capture |
| `f` | toggle favorite | new |
| `a` | add (captures text) | new |

**`vimAlias` must be applied AFTER the `/` and `a` capture branches** — otherwise
typed letters get eaten by navigation (the 3.6.0 gotcha; see playbook).

Rail left, hero right. Hero shows station artwork via the existing `ArtworkStore`
(stations carry an `artwork` attribute; cache bytes, per the 3.5.0 rule), falling
back to the gradient identicon. Live stations show a `LIVE` badge instead of a
progress bar.

### The `a` (add) flow — one affordance, two inputs

```
a → capture text, trim whitespace
  ├─ input has prefix "http://" | "https://" | "music://"  → treat as URL
  │    ├─ stationPlayURL() validates host + /station/ path
  │    │    └─ invalid → reject with a reason ("not an Apple Music station URL")
  │    ├─ parse slug + id                          (pure, always works)
  │    ├─ GET /stations?ids={id} → enrich name/artwork/isLive
  │    └─ empty → name = titlecased slug, identicon, isLive = nil
  └─ else → catalog search (types=stations) → pick a result → favorite
```

URL detection is by **scheme prefix only** — not a heuristic. A bare
`music.apple.com/...` with no scheme is treated as a search term, and will simply
find nothing; that is acceptable and predictable. Do not try to be clever here.

Unified because the two are the same *intent*. The user shouldn't have to learn
that search is unreliable; when it fails them, the URL path always works — which
is how the BBC Radio 1 case actually arrived in this session.

## The `music now` live-station fix (step 1 — prerequisite)

Today `music now --json` emits `Unexpected output` with **exit 0** while a live
station plays; `statusline.sh` line 19 (`|| exit 0`) therefore passes the garbage
to `jq`, which dies. Playing any live station breaks the documented statusline.

This ships **first**, because the Radio tab puts a live station one keypress away
— turning a latent bug into a guaranteed one for every statusline user.

Fix: when the current track is a `URL track` **and** `duration` is
`missing value`, emit a live-station shape rather than choking:

```json
{"live": true, "station": "BBC Radio 1", "state": "playing", "speakers": [...]}
```

No `duration`/`position` keys — absent, not zero, because zero is a lie.
`statusline.sh` renders the station name with a LIVE marker. Fix at the source,
not defensively in bash.

## Error handling

| Failure | Behavior |
|---|---|
| No tokens | Live/Personal/search unavailable; **favorites still work** (self-contained URL+name). Standing "token-less behavior unchanged" rule. |
| Station won't start | `open` exits 0 regardless — it exited 0 when it opened Safari. Poll player state ~5s; if not `playing`, honest failure. |
| Network down | Search errors visibly; favorites paint from disk. |
| Malformed / non-station URL | Rejected by `stationPlayURL` (host + `/station/` path). |
| Artwork fetch fails | Gradient identicon (existing). |
| API can't resolve a pasted id | Slug name + identicon + `isLive: nil`. Not an error — the BBC Radio 1 path. |

## Testing

**Pure units:** `stationPlayURL` (rewrite; rejects non-`music.apple.com`; rejects
album/playlist paths), URL→slug+id parse, slug→display name, `StationStore`
add/remove/dedupe/round-trip, `RadioNav` reducer (cursor clamp, subview cycle),
station JSON decode from fixtures, `now` live-station JSON shape.

**Seams:** `Opener` asserts the URL and never launches Music; `RadioCatalog`'s
fetch is injected with fixtures. Both follow `ArtworkStore`'s pattern.

**Live-only — cannot be unit tested:** that `music://` works, route survival, real
audio, `music now` against a real live station. Green tests do **not** mean this
works. The user's ears are the gate — proved three sessions running (art too
small, stretched aspect, and this session `player state = playing` meaning nothing
until he confirmed he heard it).

## Dead code sweep

`__radio__`'s producer was `startRadioStation`, deleted in `6bd5bc1` (1.11.0). The
readers survived: `playlistBadge` (`PlaylistBrowserModel.swift:28`),
`PlaybackContext.swift:82-84`, `PlaylistsScene.swift:425,456`, plus two tests in
`PlaylistBrowserModelTests.swift`. Orphaned dead code, not scaffolding — remove
it. Real stations are not playlists and get no `__radio__` prefix.

## Open questions

- **Why BBC Radio 1 plays but isn't in the catalog API.** Unknown. The design
  routes around it (never depend on resolution) rather than explaining it.
- **Transport on *live* stations** — untested. Track-based transport works; live
  may differ (there is nothing to skip to on a livestream).
- **Mid-station speaker switching** — untested. Route *survival* is verified;
  changing route mid-station is not.
- **How many favorites is realistic** — if search is this shallow, curation may be
  slow. Might argue for seeding Favorites with the 6 live stations on first run.

## Verification (definition of done)

1. `swift test` green — necessary, not sufficient.
2. Live: play a favorite, a live station, and the personal station; **user
   confirms audio**.
3. Live: AirPlay route survives each.
4. Live: `music now` and `statusline.sh` both survive a live station (the bug that
   started this).
5. Live: add BBC Radio 1 by URL — it must become a working favorite despite the
   API not knowing it exists.
