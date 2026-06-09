# TODO

Current high-priority follow-ups before a broad public push.

## Current Session (2026-06-08, late — repair drifted test suite) — DONE

**Done.** Restored the test target to compile + pass. `swift build` was green but `swift test` didn't compile — 4 test files had drifted against the 1.10.0/1.11.0 refactors (one more than the initial smoke test showed; the compiler halts per-file, hiding the rest). Test-only; no production change; no version bump. **Result: 85 tests, 0 failures, 14 suites.**

- [x] `SceneInputModeTests.swift:17` — added `appQueue: AppQueueStore()` (`init(backend:appQueue:)`).
- [x] `GlobalKeymapTests.swift:17` — `.radio` → `.shuffle` (`'r'` now aliases shuffle).
- [x] `TimelineRowsTests.swift` — deleted the 4 `buildPlaylistRows`/`buildStandaloneRows` tests (removed in 1.11.0); kept `splitTrackLine`/`trackKey`.
- [x] `QueueEndTests.swift:38-43` — continuation mapping: `s` → `.shuffle` (was `r` → `.radio`); `r` now nil. (Surfaced only after the first three compiled.)
- [x] `swift test` → 85 passed, 0 failed. Playbook gotcha added (build-green ≠ test-green; iterate to true green).

**Stale doc flagged (not in scope to fix here):** `docs/playbook.md` "Current Status" header still says 1.10.0 — shipped is 1.11.1. Candidate for `/kerd:trim` or a kivna pass.

---

## Backlog (from 1.9.0 → 1.11.1 session)

**Headline of prior work: the playlist track-play "regression" was Apple's, not ours, and is now routed around app-side.**

- **Root cause nailed (the user was right it used to work):** `play track N of playlist X` is REGRESSED in macOS 26.x — it drops `current playlist` to the library AND bleeds into Autoplay at track end. `play playlist X` resumes at a sticky position whose backward-nav floors there (can't reach track 1). A fresh temp-playlist copy ALSO starts mid-list and clutters iCloud (synced to the user's phone — confirmed live). No Music primitive gives "playlist at track N with full up/down".
- **1.10.0 — app-owned playlist queue** (`Sources/TUI/Shell/AppQueue.swift`): the app holds the ordered track list and drives playback (play one track; `PlaybackPoller` plays the next when it stops; next/prev/Enter navigate our list). Full up/down restored, immune to the regression. **Hard dep: Music Autoplay (∞) must be OFF** (the `once` param is ignored). Verified live across 7 checks.
- **1.10.1 — playlist rail metadata cache** (`~/.config/music/playlist-meta.json`): seed instantly + refresh off-thread with retry. (A batch transiently failed under startup load, blanking 8 rows → fixed with per-clause `try` + retry-with-backoff.)
- **1.11.0 — removed the standalone TUIs + radio** (~1500 lines). Bare `music` is the only TUI now. Radio (Accessibility-walled) gone, **shuffle** in its place (`z`/`r` + end-of-queue `[S]`). Kept every CLI utility subcommand (statusline uses `music now --json`).
- **1.11.1 — scene-aware footer** (each tab's keys + global playback keys) + **prominent ♪ playlist name** on the Now tab.
- Docs reconciled (radio/standalone-TUI refs removed); `docs/playbook.md` + project memory updated with the regression + Autoplay-off + app-owned-queue + cache-batch gotchas.

**What's next (all optional — nothing blocking):**
1. **Album-context Enter-jump** still uses the broken `play track N of current playlist` (playlists fixed; albums not) — apply the app-owned-queue treatment or accept.
2. Prune the orphaned `nextEnrichmentBatch` in `Sources/TUI/PlaylistBrowserModel.swift` (dead after the cache refactor).
3. Confirm the synced `__queue__` playlists are fully gone from the user's phone (the launch sweep should have cleared them).

### Context
- **Decision locked:** don't rely on Music's queue for playlists — own it (`AppQueue`). AppleScript+REST stack unchanged. Radio removed (permission wall), not chased.
- **Autoplay-OFF is a real runtime dependency** and is NOT scriptable (absent from the sdef) — documented in README/SKILL/playbook; cannot be detected/warned programmatically.
- Worked directly on `main` (project convention). `docs/playlist-browser-ui.md` + `.claude/` intentionally untracked.

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
