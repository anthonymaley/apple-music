#!/bin/bash
# Apple Music status line for Claude Code
# Shows currently playing track at the bottom of the terminal
#
# Setup: Add to ~/.claude/settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "~/.claude/plugins/music/scripts/statusline.sh"
#   }

cat > /dev/null  # consume stdin (Claude Code session JSON)

osascript -e '
tell application "Music"
    if player state is playing then
        return "▶ " & name of current track & " — " & artist of current track
    else if player state is paused then
        return "⏸ " & name of current track & " — " & artist of current track
    else
        return ""
    end if
end tell' 2>/dev/null
