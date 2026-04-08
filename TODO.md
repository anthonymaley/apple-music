# TODO

Current high-priority follow-ups before a broad public push.

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
