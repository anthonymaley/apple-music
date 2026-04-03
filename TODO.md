# TODO

## Current Session

- [x] Updated README, SKILL.md, guide.md for v1.3.0
- [x] Bumped version to 1.3.0 in plugin.json and marketplace.json (x2)
- [x] Added real screenshots to README (now playing, playlist browser, speakers)
- [x] Fixed README contract drift (playlist description, setup matrix, statusline path)
- [x] Fixed comma in playlist names (linefeed delimiter instead of comma split)
- [x] Raised track limit from 50 to 200
- [x] Fixed speaker name overlap (longest match wins)
- [x] Fixed statusline.sh path in comment header
- [x] Updated plugin descriptions with clearer auth messaging
- [x] Shortened now-playing footer so v Volume fits on screen
- [x] Created GitHub release v1.3.0 with full changelog
- [x] Posted to Claude Discord

## What's Next

- Consider adding video demo (cli-final.mp4) to README once GitHub supports inline video or convert to GIF
- Playlist browser: load more than 200 tracks incrementally
- Playlist browser: re-enable artwork (needs chafa raw-mode compatibility fix)
- Playlist browser: add `/` search within playlists and tracks
- Now playing: consider `n`/`p` as alternative skip keys (non-repeating)
- Volume mixer: highlight selected channel more strongly
- Consider per-speaker stop via slash command (`/music:stop kitchen`)
- End-to-end testing: playlist with comma in name, overlapping speaker names, 200+ track playlist

## Key Context

- Version is 1.3.0 everywhere (plugin.json, marketplace.json x2, CLI, guide.md)
- GitHub release: https://github.com/anthonymaley/music/releases/tag/v1.3.0
- CLI binary is `music`, installed at `~/.local/bin/music`
- Media files in `media/` folder (nowplaying.png, playlist.jog.jpg, speakers.png, cli-final.mp4)
- **2-screen flow**: PlaylistBrowser ↔ NowPlaying with PlaybackContext. b/Esc returns to browser with state preserved
- **Modal subflows**: s = speaker picker, v = volume mixer — both exit/re-enter raw mode
- **chafa**: `--format symbols` required to avoid iTerm2 inline image protocol. Disabled in playlist browser (raw mode conflict)
- **Key reader**: one-byte-at-a-time parsing. VMIN/VTIME via UnsafeMutableRawPointer
- **Radio**: builds `__radio__TrackName` temp playlist from catalog search. System Events menu approach broken on macOS 26
- **Track limit**: 200 per playlist in browser. Large library playlists ("Music") can still be slow
- **Playlist names**: use linefeed delimiter, not comma split (comma in names was a bug)
- **Speaker matching**: longest match wins (avoids "Office" matching before "Julie office")

## Backlog

- Playlist browser: incremental track loading beyond 200
- Playlist browser: artwork support (chafa + raw mode)
- Playlist browser: `/` search
- Video demo in README
- `/music:list` command for listing playlists
