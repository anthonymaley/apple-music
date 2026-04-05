# TODO

## Current Session

- [x] TUI keybindings: z cycles shuffle/repeat, r radio, l love, d dislike, +/- volume
- [x] Inherited-session wake detection in Play command (auto-wake non-local AirPlay speakers)
- [x] v1.5.0 release: keybindings + inherited wake + love/dislike
- [x] TUI rendering overhaul: 3-column layout, timeline pane, dirty-region rendering
- [x] Timeline redesign: Played (real session history) + Next (upcoming only)
- [x] Two-marker system: green ▶ = playing, cyan ▸ = cursor
- [x] Cursor movement instant (no AppleScript poll, timeline-only redraw)
- [x] Remove screen clear flicker (overwrite in place)
- [x] Playlist browser: highlight-only on ↑↓, explicit Enter/Tab to load tracks
- [x] Fix playlist name quoting (Bluecoats "Lucy" hang)
- [x] Standalone TUI: cursor navigation with Enter to play
- [x] Sync standalone TUI timeline with context-aware design
- [x] v1.6.1 release: rendering overhaul + playlist browser + bug fixes
- [x] Update skill with routed playback, wake, TUI controls

## What's Next

- Clean up worktree branch `worktree-airplay-resilience`
- Fix /kerd:tend warnings: add kivna/input/ and kivna/output/ to .gitignore, register hooks
- End-to-end edge case testing: comma in playlist name, overlapping speakers, 200+ tracks
- TUI: progress-only redraw on poll tick (Phase 2 dirty regions)
- TUI: row-only redraw on cursor move (micro-optimization)
- TUI: deferred preview in playlist browser (300-500ms idle fetch)
- Consider: playlist browser sorting (alphabetical option)
- Monitor community feedback on v1.6.1

## Key Context

- Version is 1.6.1 everywhere (plugin.json, marketplace.json x2, CLI, Music.swift)
- CLI binary is `music`, installed at `~/.local/bin/music`
- **Must codesign after cp**: `codesign -f --sign - ~/.local/bin/music` — macOS kills unsigned binaries
- **renderShell no longer clears screen** — clear only happens once at TUI startup
- **Dirty regions**: cursor ↑↓ calls refreshTimelineOnly() + continue, skips poll entirely
- **Real history only**: Played section uses in-memory history array, not playlist index position
- **Playlist name escaping**: double quotes in names escaped with `replacingOccurrences(of: "\"", with: "\\\"")`
- **2-screen flow**: PlaylistBrowser ↔ NowPlaying with PlaybackContext. b/Esc returns to browser with state preserved
- **Speaker matching**: longest match wins (avoids "Office" matching before "Julie office")
- **Wake cycle**: deselect→500ms→reselect→500ms→verify. Inherited-session wake auto-detects non-local speakers.
- **SourceKit false positives**: cross-file symbol warnings are noise. Build compiles clean.

## Backlog

- Playlist browser: incremental track loading beyond 200
- Playlist browser: artwork support (chafa + raw mode)
- Playlist browser: `/` search
- Video demo in README
- `/music:list` command for listing playlists
