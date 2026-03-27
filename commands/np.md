---
name: np
description: Show what's currently playing in Apple Music
disable-model-invocation: true
---

Now playing:

!`osascript -e 'tell application "Music"
    if player state is playing then
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        return "▶ " & trackName & " — " & trackArtist & " (" & trackAlbum & ")"
    else if player state is paused then
        set trackName to name of current track
        set trackArtist to artist of current track
        return "⏸ " & trackName & " — " & trackArtist & " (paused)"
    else
        return "■ Nothing playing"
    end if
end tell' 2>/dev/null || echo "■ Music app not running"`
