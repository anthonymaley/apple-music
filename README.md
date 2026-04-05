# Apple Music for Claude Code

```
     ___              __        __  ___         _
    / _ | ___  ___   / /__     /  |/  /_ _____ (_)___
   / __ |/ _ \/ _ \ / / -_)   / /|_/ / // (_-</ / __/
  /_/ |_/ .__/ .__/_/\__/   /_/  /_/\_,_/___/_/\__/
       /_/  /_/
                    for Claude Code & CLI
```

Control Apple Music, AirPlay speakers, and AirPods from Claude Code or the terminal.

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                                                                     │
  │  you:  Go find the latest deep house tracks, put them in a          │
  │        playlist, shuffle it on the kitchen at 60%, and list         │
  │        the tracks here for me.                                      │
  │                                                                     │
  │  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐  │
  │    music search "deep house 2026" --limit 15                       │
  │  │ music playlist create "Deep House Finds" 1 3 5 7 9           │  │
  │    music speaker kitchen 60                                        │
  │  │ music shuffle on                                              │  │
  │    music play "Deep House Finds"                                   │
  │  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  │
  │                                                                     │
  │  claude:  Playing Deep House Finds on Kitchen [60]                  │
  │                                                                     │
  │    1. Silhouette — Kerri Chandler                                   │
  │    2. Night Ride — Fouk                                             │
  │    3. Body Movement — DJ Seinfeld                                   │
  │    4. Midnight Sun — Jimpster                                       │
  │    5. Inner City Blues — Moodymann                                   │
  │                                                                     │
  │  you:  It's great. Share it with Julie on iMessage.                 │
  │  claude:  Shared "Deep House Finds" with Julie via iMessage.        │
  │                                                                     │
  ├─────────────────────────────────────────────────────────────────────┤
  │  ▶ Silhouette — Kerri Chandler  ·  Kitchen [60]                    │
  └─────────────────────────────────────────────────────────────────────┘
```

## Three Ways to Use It

| Layer | How | Setup | Token cost |
|-------|-----|-------|-----------|
| **Slash commands** (`/music:play`) | Type and run, instant | None | None |
| **CLI** (`music now`, `music speaker`) | Terminal commands, TUI, scriptable | Build from source | None |
| **CLI + API** (`music search`, `music playlist create`) | Catalog, library, discovery | + Apple Developer account | None |
| **Natural language** ("play house on the kitchen") | Claude orchestrates CLI calls | Depends on features used | Normal |

## Install

### Claude Code (CLI)

```bash
# Add the marketplace
/plugin marketplace add anthonymaley/music

# Install the plugin
/plugin install music@anthonymaley-music
```

### Claude Desktop App (Cowork)

1. Click **+** next to the prompt box
2. Select **Plugins**
3. Choose **Add plugin**
4. Browse and select **Apple Music**

### Update

```bash
# CLI
claude plugin update music@anthonymaley-music

# Desktop — Manage plugins → Update
```

### Advanced Features (optional, requires Apple Developer account)

Playback, speakers, and volume work out of the box with zero setup. For catalog search, library management, playlists via API, and music discovery, you need:

1. An **Apple Developer account** ($99/year at [developer.apple.com](https://developer.apple.com))
2. The **music CLI** built from source
3. A **MusicKit key** configured via guided setup

```bash
# Build the CLI
cd ~/.claude/plugins/cache/music@anthonymaley-music
scripts/install.sh

# Guided auth setup — walks you through creating a MusicKit key
music auth setup

# Get your user token (opens browser, auto-saves)
music auth

# Verify
music auth status
```

After updating the plugin, rebuild the CLI: `scripts/install.sh`

## Slash Commands

Instant execution. No AI reasoning, no token cost. Type `/music:` and tab to discover.

### Playback

| Command | What it does |
|---------|-------------|
| `/music:play` | Resume playback |
| `/music:play Working Vibes` | Play a playlist |
| `/music:play Working Vibes kitchen 60` | Play on a speaker at volume |
| `/music:play Working Vibes shuffle` | Shuffle a playlist |
| `/music:play 3` | Play result #3 from last search/playlist |
| `/music:pause` | Pause |
| `/music:skip` | Next track |
| `/music:back` | Previous track |
| `/music:stop` | Stop playback |
| `/music:stop kitchen` | Remove kitchen from speaker group |
| `/music:now` | What's playing (track, album, speakers) |
| `/music:shuffle` | Toggle shuffle on/off |
| `/music:radio` | Start a radio station from what's playing |

### Speakers & Volume

| Command | What it does |
|---------|-------------|
| `/music:speaker` | Interactive picker with ←→ volume control |
| `/music:speaker kitchen` | Add kitchen to active speakers |
| `/music:speaker kitchen 40` | Add kitchen at volume 40 |
| `/music:speaker kitchen stop` | Remove kitchen from group |
| `/music:speaker airpods only` | Switch to AirPods only |
| `/music:speaker wake` | Wake all active speakers (fix ghost connections) |
| `/music:speaker wake kitchen` | Wake a specific speaker |
| `/music:speaker 1 2 5` | Add speakers by number from last list |
| `/music:volume` | Interactive per-speaker volume mixer |
| `/music:volume 60` | Set all active speakers to 60 |
| `/music:volume up` / `down` | Volume ±10 |
| `/music:volume kitchen 80` | Set a specific speaker to 80 |

### Playlists

| Command | What it does |
|---------|-------------|
| `/music:playlist list` | List all playlists |
| `/music:playlist tracks Working Vibes` | Show tracks in a playlist |

### Catalog & Discovery (requires auth)

| Command | What it does |
|---------|-------------|
| `/music:search Bohemian Rhapsody` | Search Apple Music catalog (100M+ tracks) |
| `/music:add Get It Done Fouk` | Add a track to your library |
| `/music:add 3` | Add result #3 from last search |
| `/music:similar` | Similar tracks with play/add/create actions |

## CLI Commands

```
  ┌─────────────────────────────────────────────────────────────┐
  │  Requires Apple Developer account ($99/yr) + build from     │
  │  source. See "Advanced Features" above for setup.           │
  └─────────────────────────────────────────────────────────────┘
```

### Playlist Management

| Command | What it does |
|---------|-------------|
| `music playlist create "Friday Mix"` | Create an empty playlist |
| `music playlist create "Friday Mix" 1 3 5` | Create from search result indices |
| `music playlist add "House" 1 3 5` | Add search results to existing playlist |
| `music playlist delete "Old Playlist"` | Delete a playlist |
| `music playlist remove "House" "Song"` | Remove a track from a playlist |
| `music playlist share "Mix" --imessage "+1234567890"` | Share via iMessage |
| `music playlist share "Mix" --email "a@b.com"` | Share via email |
| `music playlist create-from "Song" "Artist" ... --name "Mix"` | Create + populate from title/artist pairs |
| `music playlist temp "Song" "Artist" ...` | Temp playlist, auto-cleanup |

### Library

| Command | What it does |
|---------|-------------|
| `music add --to "House"` | Add current song to a playlist |
| `music add 3 --to "House"` | Add result #3 to a playlist |
| `music remove` | Remove current song from current playlist |
| `music remove "House"` | Remove current song from "House" |
| `music remove all` | Remove current song from all playlists |

### Discovery

| Command | What it does |
|---------|-------------|
| `music similar` | Similar to what's playing |
| `music suggest 10 --from "Working Vibes"` | Suggest tracks from playlist vibe |
| `music new-releases --like-current` | New releases from current artist |
| `music mix --artists "Fouk,Floating Points" --name "Friday Mix"` | Mixed playlist |

### Routed Playback

Play music on a specific speaker in one command. The CLI parses the speaker name from your args using longest-match against live AirPlay devices.

```bash
music play "Working Vibes" kitchen 20          # play on Kitchen at volume 20
music play "Working Vibes" kitchen 20 shuffle  # with shuffle
music play "Working Vibes" "sonos arc" 60      # multi-word speaker names
```

A wake cycle runs automatically when a speaker is detected — deselects then reselects the speaker to fix the common AirPlay "ghost connection" problem where a speaker shows as connected but isn't playing audio.

**Inherited-session wake:** If Apple Music is already playing to an AirPlay speaker from a previous session, `music play` (with or without a playlist name) auto-detects the non-local speakers and wakes them before playback. No need to specify the speaker name — it just works.

Use `--no-wake` to skip it, or `--verbose` to see each step:

```bash
music play "Working Vibes" kitchen 20 --verbose  # see wake cycle steps
music play "Working Vibes" kitchen 20 --no-wake  # skip wake cycle
```

For mid-session speaker recovery:

```bash
music speaker wake              # wake all active speakers
music speaker wake kitchen      # wake a specific speaker
```

### Diagnostics

Add `--verbose` (`-v`) to any command for diagnostic output on stderr:

```bash
music speaker smart --verbose wake kitchen   # see deselect/reselect/verify steps
music play --playlist "Working Vibes" -v     # see AppleScript calls
music speaker smart --verbose list --json    # verbose on stderr, JSON on stdout
```

### JSON Output

Every command supports `--json` for scripting and automation:

```bash
music now --json          # structured now-playing
music search "Fouk" --json --limit 20   # structured search results
music playlist list --json               # structured playlist list
```

```
  ┌─────────────────────────────────────────────────────────────┐
  │  End of Apple Developer account section. Everything below    │
  │  works with zero setup.                                      │
  └─────────────────────────────────────────────────────────────┘
```

## Natural Language (Skill)

For anything multi-step, just talk. Claude composes the right sequence of CLI calls automatically.

```
> Look at the Working Vibes playlist. See the last ten tracks on that
  playlist. Make a separate playlist with those ten tracks and shuffle
  them. Play it on the kitchen and Sonos Arc at 60%.

> Take the current track and search for new records that match this
  style. Put them in a playlist and shuffle them.

> It's great. Share it with Julie on iMessage.

> Switch to my AirPods and turn it down to 30.

> Add the bedroom to the group and turn the kitchen down to 40.

> What's new from Radiohead? Make a playlist of the best ones.
```

Claude handles multi-step orchestration — searching the catalog, creating playlists, routing to speakers, setting volume, sharing — all from one sentence.

## Interactive TUI

Run these commands in a real terminal (not inside Claude Code — TUI requires a TTY). Install `chafa` (`brew install chafa`) for album art in now-playing.

**Now playing** (`music now`) — album art, progress bar, queue, full playback controls. Shows `▶`/`⏸` play state and `Shuffle`/`Repeat` indicators.

| Key | Action |
|-----|--------|
| `↑`/`↓` | Skip track (scroll queue in playlist mode) |
| `←`/`→` | Seek ±30s |
| `Space` | Play/pause |
| `z` | Cycle mode: off → shuffle → repeat all → repeat one → off |
| `r` | Start radio station from current track |
| `l` | Love current track (toggles) |
| `d` | Dislike current track (toggles) |
| `+`/`-` | Master volume ±5 |
| `s` | AirPlay speaker picker |
| `v` | Per-speaker volume mixer |
| `b`/`Esc` | Back (playlist mode) / Quit |
| `q` | Quit |

![Now Playing](media/nowplaying.png)

**Playlist browser** (`music playlist`) — 2-pane browser. Left: playlists. Right: scrollable tracks. `Tab` switches panes, `Enter` plays a track and transitions to Now Playing. `b` returns here.

![Playlist Browser](media/playlist.jog.jpg)

**Speaker picker** (`music speaker`) — toggle AirPlay outputs on/off, adjust per-speaker volume with `←→`. Active speakers show volume bars.

![Speaker Picker](media/speakers.png)

## Status Line

See what's playing at the bottom of Claude Code. Always visible, no token cost.

```
┌──────────────────────────────────────────────────────────────┐
│  claude >                                                    │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  ▶ Everything In Its Right Place — Radiohead  ·  Kitchen [60]│
└──────────────────────────────────────────────────────────────┘
```

Add to `~/.claude/settings.json` (adjust the path to your plugin cache location):

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/plugins/cache/music@anthonymaley-music/scripts/statusline.sh"
  }
}
```

## What Needs Auth?

| Feature | No auth | Developer token | + User token |
|---------|---------|----------------|-------------|
| Play, pause, skip, stop, shuffle, repeat | Yes | Yes | Yes |
| Speakers, volume, now playing | Yes | Yes | Yes |
| Catalog search | — | Yes | Yes |
| Add to library | — | — | Yes |
| Playlist CRUD via API | — | — | Yes |
| Similar, suggestions, new releases, mix | — | — | Yes |

## How It Works

The plugin routes through the `music` CLI when installed. Without it, playback and speaker commands fall back to raw AppleScript.

```
  Slash Commands ──► music CLI ──► AppleScript (playback, speakers, volume)
       │                   └──► REST API (catalog, library, playlists, discovery)
       └──► AppleScript (fallback when music CLI not installed)
```

Search results are cached locally (`~/.config/music/last-songs.json`). When you run `music search`, `music similar`, or view playlist tracks, the numbered results persist so you can reference them by index in follow-up commands like `music play 3` or `music add 3 --to "House"`. Play commands show full now-playing info (track, album, speakers) after starting playback.

Speaker lists work the same way (`~/.config/music/last-speakers.json`). Run `music speaker list`, then `music speaker 1 2 5` to add speakers by their numbers.

## Requirements

- **macOS** (AppleScript is macOS only)
- **Apple Music** (comes with macOS)
- **Automation permission** (System Settings > Privacy & Security > Automation > enable for your terminal)
- **Swift 5.9+** (only if building the music CLI)
- **AirPods** must be connected via Bluetooth to appear as a device
- **chafa** (optional, `brew install chafa` — enables album art in now-playing TUI)

## License

MIT
