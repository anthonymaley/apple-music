# Real album covers in the Library and Playlists tabs

**Date:** 2026-07-14 · **Status:** approved design, pre-implementation · **Ships as:** 3.5.0

## Problem

The Library hero pane (`LibraryScene.swift` `renderHero`) and the Playlists hero
both draw `gradientBlock(name:)` — a deterministic identicon seeded from the
name, not artwork. Only the Now tab shows real covers (AppleScript raw-data →
`artworkToAscii`). The user wants real covers in BOTH tabs (his word: "BOTH").

## Verified facts (live-probed 2026-07-14, not training data)

- `/v1/me/library/albums` → `attributes.artwork.url` is a **stable mzstatic CDN
  template** containing `{w}x{h}` (e.g. `…/18UMGIM31076.rgb.jpg/{w}x{h}bb.jpg`).
  Substitute e.g. `300x300` and GET.
- `/v1/me/library/playlists` → `attributes.artwork.url` is a **pre-signed S3 URL**
  (`X-Amz-Expires=86400`, 24h) with **no `{w}x{h}` template** — fetch as-is.
  Some playlists have no artwork attribute at all.
- Consequence: **cache bytes, never URLs.** The fetcher must handle both shapes:
  substitute `{w}x{h}` when present, otherwise use the URL verbatim.
- Both endpoints need the user token — which the Library tab already requires.
  The Playlists tab works token-less today and must keep doing so.
- `artworkToAscii(path:width:height:)` (NowPlayingTUI.swift) already renders any
  image file: chafa truecolor half-blocks, CoreGraphics `░▒▓█` mono fallback.
  Reused as-is; no new rendering code.

## Design

### ArtworkStore (new, `TUI/ArtworkStore.swift`)

One small component owning fetch + cache + render for both scenes:

- `resolveURL(template:width:height:) -> String` — pure: `{w}x{h}` substitution
  or passthrough. Unit-tested against both live shapes.
- Byte cache on disk: `~/.config/music/art-cache/<key>` where key =
  sanitized resource id (library album id / REST playlist id). Download once,
  ever; cache hit skips the network entirely (playlist URL expiry is therefore
  harmless after first fetch).
- Rendered-lines cache in memory keyed `(key, w, h)` so re-focusing is instant.
- Per-session negative cache (failed fetch / no artwork) so a broken URL never
  retries in a loop.
- HTTP via an injectable `(URL) -> Data?` closure — seam for unit tests, same
  pattern as RouteHealer's injectable backend. No network in tests.

### Library wiring

- `LibraryAlbum` gains `artworkURL: String?`; `parseLibraryAlbums` reads
  `attributes.artwork.url` (missing → nil).
- `renderHero`: if rendered lines cached → draw them; else draw the existing
  gradient AND kick one background fetch+render, delivering through the scene's
  existing inbox + `tick` discipline (pending buffer under `inboxLock`, main
  list mutated only in `tick` — same rule as the streaming loads). Art swaps in
  on a later tick.

### Playlists wiring

- The scene is AppleScript-backed and stays that way. After scene load, if a
  user token exists, one background paginated walk of `/v1/me/library/playlists`
  builds a `lowercased-trimmed name → (restID, artworkURL)` map (name matching —
  the same heuristic and known-limitation class as `albumArtistSet`).
- Hero render: map hit → ArtworkStore flow as above; no map entry (smart/local
  playlists such as "Recently Played"), no token, or no artwork → gradient
  stays, exactly today's behavior.

### Fallback ladder (both tabs)

real cover → (while loading / on any failure / token-less) gradient identicon →
(no chafa) mono-block art. No error states are surfaced; art is decoration.

## Testing

- Pure unit tests: `resolveURL` both shapes, cache-key sanitization, artwork
  field parsing (present/absent), playlist name-map matching.
- Seam tests: ArtworkStore with fake HTTP closure — hit/miss/negative-cache
  paths; renderer injected as a fake returning known lines.
- Suite stays offline and <1s growth. Live verification is manual (below).

## Live verification plan

1. Library → focus an album: gradient first paint, real cover within ~a beat;
   re-focus instant (memory cache); relaunch instant (disk cache).
2. Playlists → cloud playlist shows cover; "Recently Played"/"Top 25" keep
   gradient (honest gap, by design).
3. Move `~/.config/music/user-token` aside: both tabs behave exactly as today
   (gradients, no errors), token restored after.

## Out of scope

Per-row thumbnails (illegible at cell resolution), Now-tab changes, site/demo
re-recording, AppleScript artwork for arbitrary albums (whose-clause scan is
seconds-slow and rides the macOS 26 scripting regressions).
