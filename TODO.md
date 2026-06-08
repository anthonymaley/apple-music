# TODO

Current high-priority follow-ups before a broad public push.

## Current Session (2026-06-08)

**Done this session (v1.8.0 → 1.9.0, 48 commits, all on main, all pushed):**
- **Unified TUI shell** — bare `music` now launches one navigable app (was a pile of one-shot screens). Built spec→plan→subagent-driven across milestones:
  - **M1 (spine):** background `PlaybackPoller` thread + lock-guarded `NowPlayingStore`, single `runShell` loop, `Router` (scene stack), `ShellFrame` (degradation tiers), global keymap, `Scene` protocol, Now Playing scene. Auto-advance/history/album-context moved into the poller.
  - **M2 (Playlists scene):** v1.8.0 3-zone browser pulled into the shell as tab 2; `PlaylistDataSources` factory; `capturesAllInput` for filter text-entry.
  - **M2b (Speakers scene):** merged the AirPlay picker + per-speaker volume mixer into one tab 3.
  - Shipped **1.9.0** (4 version locations).
  - **M3 (Now Playing rework + Playlists polish):** real album-art hero (`extractArtwork`+chafa) + Up Next from playback context; two-pane layout (art/meta left, Up Next right); highlight-line track rows (consistent indent, lime ▶ current, inverse cursor) with capped width; bigger art; Playlists preview fills the pane; current marked by index not title.
  - **End-of-queue continuation:** pure detection guard + card menu (Radio / Playlist / Quiet) + manual `n` trigger; fires on STOP (the common case), not just autoplay-to-library.
- **Architecture research** (ultracode workflow, 37 agents, verified vs Apple docs + live): VERDICT = **AppleScript (control) + REST (data) is the only viable stack.** MusicKit/MediaPlayer/MediaRemote/browser all rejected (native-macOS-unavailable / paid-dev-account entitlement / private API). Saved to memory [[project_apple_music_integration_architecture]].

**⚠ In progress — committed but NOT verified live (the next session MUST confirm before claiming fixed):**
- **R5 playlist context** — `play track N of playlist X` collapses `current playlist` to the library (26.x regression, reproduced live). Fix (`521ffef`): play a temp `__queue__` tail playlist instead. The user's last screenshot was the OLD binary — fix not yet tested.
- **Native radio** (`r` / `[R]`) — Create Station via System Events GUI-click. Works from Terminal manually (activate-first). From the `music` binary: Music activates but the **click is a no-op** → almost certainly the binary lacks **Accessibility** permission (a stricter TCC category than Apple Events). Likely a hard wall. Do NOT ship a 4th same-shape patch (see shame point below).
- **Bottom now-playing bar removed** (`d1e7f84`) per user — playback lives on the Now tab. Not yet seen live.

**What's next:**
1. **User reinstalls** (`scripts/install.sh`) and verifies R5 (does playlist context hold?), the bar removal, and radio — the last screenshot predates all three.
2. **R5:** if Up Next still shows the alphabetical library after reinstall, the temp-queue approach also fails → document R5 as a platform limit.
3. **Radio:** if `r` still no-ops after Music activates → confirmed Accessibility wall → decide **home-built mix** vs **document as manual**. Don't keep patching Swift.
4. **Bump 1.10.0** only after R5 + radio are settled (folds in M3 + end-of-queue + R5 + bar removal).

### Context
- **Decision:** keep AppleScript+REST; MusicKit/MediaPlayer/browser are evaluated-and-rejected (memory). R5/R6(radio)/R7(real queue) are platform/permission gaps, not bugs.
- **The 89 unit tests are pure-model only** (zones/parsing/router/frame math) — they prove NOTHING about playback context, AirPlay, radio, or permissions. Build-green ≠ live-verified. (Shame point captured this session: `green-build-is-not-a-live-fix` — I shipped 3 fixes on green builds, each failing live.)
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
