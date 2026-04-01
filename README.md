# Apple Music for Claude Code

```
     ___              __        __  ___         _
    / _ | ___  ___   / /__     /  |/  /_ _____ (_)___
   / __ |/ _ \/ _ \ / / -_)   / /|_/ / // (_-</ / __/
  /_/ |_/ .__/ .__/_/\__/   /_/  /_/\_,_/___/_/\__/
       /_/  /_/
                         for Claude Code
```

Control Apple Music, AirPlay speakers, and AirPods from your terminal.

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

## What You Can Do

Talk to Claude. These are real examples:

```
> Look at the Working Vibes playlist. See the last ten tracks on that
  playlist. Make a separate playlist with those ten tracks and shuffle
  them. Play it on the kitchen and Sonos Arc at 60%.

> Take the current track and search for new records that match this
  style. Put them in a playlist and shuffle them.

> It's great. Share it with Julie on iMessage.

> Switch to my AirPods and turn it down to 30.

> Add the bedroom to the group and turn the kitchen down to 40.
```

Claude handles the multi-step orchestration. Searching the catalog, creating playlists, routing to speakers, setting volume, sharing. All from one sentence.

All commands start with `/music:`. Type `/music:` and tab to discover them.

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

## Commands

Every command runs instantly. No AI reasoning, no token cost.

### Playback

| Command | What it does |
|---------|-------------|
| `/music:play` | Resume playback |
| `/music:play Working Vibes` | Play a playlist |
| `/music:play Working Vibes shuffle` | Play a playlist with shuffle |
| `/music:play 3` | Play result #3 from your last search |
| `/music:pause` | Pause |
| `/music:skip` | Next track |
| `/music:back` | Previous track |
| `/music:stop` | Stop playback |
| `/music:stop kitchen` | Remove kitchen from the speaker group |
| `/music:now` | Show what's currently playing |
| `/music:shuffle` | Toggle shuffle on/off |

### Speakers

| Command | What it does |
|---------|-------------|
| `/music:speaker` | Interactive picker: browse, toggle with spacebar |
| `/music:speaker list` | List all AirPlay devices |
| `/music:speaker kitchen` | Add kitchen to active speakers |
| `/music:speaker kitchen 40` | Add kitchen and set volume to 40 |
| `/music:speaker kitchen stop` | Remove kitchen from the group |
| `/music:speaker airpods only` | Switch to AirPods only |
| `/music:speaker 1 2 5` | Add speakers by number from last list |

### Volume

| Command | What it does |
|---------|-------------|
| `/music:volume` | Interactive mixer: per-speaker bars, arrow keys to adjust |
| `/music:volume 60` | Set all active speakers to 60 |
| `/music:volume up` | Volume +10 |
| `/music:volume down` | Volume -10 |
| `/music:volume kitchen 80` | Set a specific speaker to 80 |

### Playlists & Library

| Command | What it does | Setup |
|---------|-------------|-------|
| `/music:playlist` | Interactive browser: pick a playlist, see tracks | none |
| `/music:playlist list` | List all your playlists | none |
| `/music:playlist tracks Working Vibes` | Show tracks in a playlist | none |
| `/music:playlist create Friday Mix` | Create an empty playlist | advanced |
| `/music:playlist create Friday Mix 1 3 5` | Create from last search results | advanced |
| `/music:playlist add "House" 1 3 5` | Add results to existing playlist | advanced |
| `/music:playlist delete Old Playlist` | Delete a playlist | advanced |
| `music add --to "House"` | Add current song to a playlist | advanced |
| `music add 3 --to "House"` | Add result #3 to a playlist | advanced |
| `music remove` | Remove current song from current playlist | advanced |
| `music remove all` | Remove current song from all playlists | advanced |

### Catalog & Discovery (advanced)

| Command | What it does |
|---------|-------------|
| `/music:search Bohemian Rhapsody` | Search Apple Music catalog (100M+ tracks) |
| `/music:search Fouk` | Search by artist |
| `/music:add Get It Done Fouk` | Add a track to your library |
| `/music:add 3` | Add result #3 from last search |
| `/music:similar` | Interactive browser: similar tracks with play/add/create actions |

### Interactive TUI

Commands that browse lists launch a terminal UI when you run them with no arguments. Arrow keys to navigate, spacebar to select, letter keys for actions.

```
  AirPlay Speakers

   ✓  1. Anthony's MacBook Pro — vol: 15
   ✓  2. Kitchen — vol: 60
      3. Living Room — vol: 60
      4. Bedroom — vol: 60

  ↑↓ navigate  ␣ select  q quit  (2 selected)
```

```
  Volume Mixer

  Kitchen        [████████████░░░░░░░░] 60%
  MacBook Pro    [███░░░░░░░░░░░░░░░░░] 15%

  ↑↓ speaker  ←→ volume (±5%)  0-9 quick-set  q quit
```

These only activate in a TTY. Piped output stays non-interactive, so scripts and Claude's `--json` mode work as before.

## Natural Language

Slash commands handle quick actions. For anything multi-step, just talk. Claude composes the right sequence of CLI calls automatically. See [What You Can Do](#what-you-can-do) above for examples.

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

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/plugins/music/scripts/statusline.sh"
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

Search results are cached locally (`~/.config/music/last-songs.json`). When you run `music search` or `music similar`, the numbered results persist so you can reference them by index in follow-up commands like `music play 3` or `music add 3 --to "House"`.

Speaker lists work the same way (`~/.config/music/last-speakers.json`). Run `music speaker list`, then `music speaker 1 2 5` to add speakers by their numbers.

## Requirements

- **macOS** (AppleScript is macOS only)
- **Apple Music** (comes with macOS)
- **Automation permission** (System Settings > Privacy & Security > Automation > enable for your terminal)
- **Swift 5.9+** (only if building the music CLI)
- **AirPods** must be connected via Bluetooth to appear as a device

## License

MIT
