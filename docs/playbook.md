# Playbook: Apple Music

How to rebuild this project from scratch.

## Tech Stack
Claude Code plugin using AppleScript via `osascript` for macOS Music app control.

## Setup
1. Install the plugin: `/install github:anthonymaley/music`
2. Grant automation permissions: System Settings > Privacy & Security > Automation
3. Optional: enable status line in `~/.claude/settings.json` (see README)

## Architecture
Three-layer plugin:
- `skills/apple-music/SKILL.md` — conversational skill for complex multi-step requests (e.g. "play Kid A on the kitchen speaker")
- `commands/` — slash commands (`/music:play`, `/music:np`, `/music:speaker`, etc.) for instant one-tap controls
- `scripts/statusline.sh` — status line script showing current track at the bottom of Claude Code

All commands use AppleScript via `osascript`. No external dependencies.

## Integrations
- macOS Music app (via AppleScript)
- AirPlay speakers and Bluetooth audio devices

## Deployment
Published via Claude Code marketplace. Version bumps must update all three locations (see CLAUDE.md).

## Gotchas
- Parameter error (-50) when using AirPlay + playback commands together — split into separate osascript calls (route first, then play)
- User must grant Automation permissions on first use
- macOS only — AppleScript doesn't exist on other platforms
- Plugin name is `music` (not `apple-music`) — commands are `/music:play`, `/music:np`, etc.
- AirPods names often contain apostrophes — must escape in bash: `'Anthony'\''s AirPods Pro'`

## Current Status
v0.2.0 in progress. Added quick commands (`/music:play`, `/music:pause`, `/music:skip`, `/music:back`, `/music:stop`, `/music:np`, `/music:speaker`) and status line script. Plugin renamed from `apple-music` to `music` for shorter commands. README rewritten with ASCII art, real session examples, and full guide.
