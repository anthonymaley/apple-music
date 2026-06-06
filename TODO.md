# TODO

Current high-priority follow-ups before a broad public push.

## Current Session (2026-06-06)

**Done this session (v1.7.0 → v1.8.0, 18 commits, all on main):**
- Deep review of skill + CLI, then fixes in 3 batches: AppleScript escaping hardened (one `escapeAppleScriptString` helper, backslash-then-quote, all user/catalog values routed through it; `repeat` mode validated); TUI poll now returns `PollOutcome {active|stopped|unavailable}` so a transient hiccup no longer skips a track or blanks the UI; SIGWINCH wired; dead code purged; docs/install-id/version drift fixed; CLI `--version` is a 4th version-sync location (documented in CLAUDE.md).
- Fixed the playlist-browser rendering corruption (`clearBody` — clear body rows before repaint).
- **Full playlist-browser redesign (`music playlist`) → 3-zone surface** (rail · hero · preview): pure model layer (`PlaylistBrowserModel.swift`, 21 unit tests), progressive tick-driven metadata enrichment (counts/duration/SMART·RADIO·RECENT badges, visible-first, status line), hero card (gradient block + subtitle + actions), right-panel preview (8 tracks on cursor-settle), client-side `/` filter, Enter→scrollable track list, five-role color palette. Built subagent-driven from spec→plan; each rendering task user-verified live.
- **Perf fix:** `onTracks` replaced `repeat with t in (every track…)` (~3.77s on the 13k-track library playlist) with bulk `name/artist of tracks 1 thru n` (~0.21s, verified by measurement). Same for `onPreview`. Preview fetch gated to visible pane; enrichment made filter-correct.
- Bumped to **v1.8.0** across all 4 locations; CLI reinstalled and `--version` verified.

**In progress:** none — redesign complete and live.

**What's next / deferred (phase 2 of the redesign, by design):**
- Real playlist artwork in the hero (currently a generated gradient block).
- Right-panel `Now Playing` + `Recent` modes, `Tab` panel cycling, live now-playing polling in the browser.
- Dominant-genre line in the hero (derive from loaded track genres).
- Minor review deferrals: `dropFirst(9)` magic number; transient preview-fetch failure cached as `(empty)`; redundant Enter-path cursor reset; `visibleIndices` memoization (only matters at thousands of playlists).
- Spec/plan: `docs/superpowers/specs/2026-06-06-playlist-browser-redesign-design.md` + `docs/superpowers/plans/2026-06-06-playlist-browser-redesign.md` (features now complete — candidates for `/kerd:trim`).

### Context
- The gradient hero block reads as textured noise, not a smooth gradient — flagged as cheap to refine/drop if it feels gimmicky.
- TUI behavior is not CI-verifiable; the user verified each rendering checkpoint live on this machine.
- `docs/playlist-browser-ui.md` (user's design-notes doc) is intentionally left untracked.

## TUI Polish

- Verify `music now` album context with duplicate library entries, multi-disc albums, and albums with repeated track numbers.
- Verify radio handoff from both `music now` and playlist-origin Now Playing: generated playlist should keep playing past the first track and expose navigable rows.
- Decide whether standalone `music now` should remain album-context only or eventually expose a real queue if Apple Music exposes a reliable source.
- Keep playlist-origin Now Playing as the stable full-playlist view; avoid reintroducing a tail-only queue model there.
- Watch for terminal redraw artifacts on transparent terminals; prefer targeted row clears over full-screen redraws.

## Playback Semantics

- Confirm playlist-origin playback continues naturally at track end after direct `play track N of playlist ...`.
- Keep `z` as shuffle-only in the TUI unless repeat gets its own explicit key.
- Do not auto-reset AirPlay outputs during normal playback. Use `music speaker wake` for explicit ghost-speaker recovery.

## Docs

- Keep README, `skills/music/SKILL.md`, and `docs/guide.md` aligned whenever TUI keys or AirPlay behavior changes.
- Treat `docs/superpowers/*` as historical design/planning notes unless a new implementation round explicitly updates them.
