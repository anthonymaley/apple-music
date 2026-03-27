---
name: back
description: Go to previous track in Apple Music
disable-model-invocation: true
---

!`osascript -e 'tell application "Music"
    back track
    delay 0.5
    return "⏮ " & name of current track & " — " & artist of current track
end tell' 2>/dev/null || echo "Could not go back"`
