---
name: play
description: Resume Apple Music playback
disable-model-invocation: true
---

!`osascript -e 'tell application "Music"
    play
    delay 0.5
    return "▶ " & name of current track & " — " & artist of current track
end tell' 2>/dev/null || echo "Could not start playback"`
