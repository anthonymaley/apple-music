# TODO

## Current Session

- [x] Fixed Speaker TUI crash (Swift exclusivity violation in onToggle callback)
- [x] Fixed play cold-start -1728 error (retry loop waits for track to load)
- [x] Added ←→ volume control to speaker TUI (onAdjust callback in MultiSelectList)
- [x] Added playlist browser action sub-menu (list tracks / shuffle play / play in order)
- [x] Playlist tracks now write to song cache (index playback works after browsing)
- [x] All play/skip/back commands show full now-playing info (track, album, speakers)
- [x] Restructured README: clear separation of slash commands, CLI, and skill sections
- [x] Updated docs (README, guide, SKILL.md) for all new features

## What's Next

- Update descriptions in plugin.json and marketplace.json to reflect CLI + Claude Code positioning
- Review SKILL.md — may need same slash/CLI/skill separation treatment as README
- Review guide.md — sync with README restructure
- Publish v1.2.0 to marketplace (or bump to 1.2.1 for this session's fixes)
- End-to-end testing of all interactive TUI modes in a real terminal
- Test Ctrl-C cleanup in each TUI view

## Key Context

- CLI binary is `music`, installed at `~/.local/bin/music`
- Config lives at `~/.config/music/` (config.json, AuthKey.p8, user-token)
- Result caches: `~/.config/music/last-songs.json`, `~/.config/music/last-speakers.json`
- Auth page served via Python HTTP server on localhost:8537
- User has Apple Developer account: Team ID `8NS66RKB45`, Key ID `W5H3NYJ999`
- All slash commands have osascript fallback if music binary not installed
- All slash commands have `disable-model-invocation: true` — instant, zero token cost
- Skill frontmatter name is `music`
- Version is 1.2.0 everywhere (plugin.json, marketplace.json x2, music CLI)
- Naming: one public name `music`, display name `Apple Music for Claude Code & CLI`
- **Critical learning**: ArgumentParser property wrappers crash when accessed on directly-constructed structs. Always use standalone functions for shared logic.
- **Critical learning**: Swift exclusivity enforcement — inout params hold exclusive access, closures that capture the same variable will crash. Use separate arrays.
- **Critical learning**: AppleScript `current track` fails with -1728 immediately after `play` — need retry loop to wait for track to load.
- showNowPlaying has `waitForPlay` param: true when called after play (retries on "stopped" state), false for `music now` (returns immediately).
- MultiSelectList has optional `onAdjust` callback for ←→ key handling — used by speaker TUI for volume.

## Backlog

- Consider per-speaker stop via slash command (`/music:stop kitchen`)
- Consider `/music:list` command for listing playlists
