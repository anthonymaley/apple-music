# media/demo.tape — TUI walkthrough demo for the README.
# Regenerate: vhs media/demo.tape   (then optimize per docs if needed)
# Requires live Apple Music auth, the "Sleep" playlist, and AirPlay speakers.
# Running this STARTS real playback (Nude — Radiohead) and selects a speaker.
# Theme "Homebrew" matches the user's macOS Terminal profile (green-on-black).

Output media/demo.gif

Require music

Set Shell "zsh"
Set Theme "Homebrew"
Set FontSize 21
Set Width 1920
Set Height 1400
Set Padding 24
Set Framerate 24
Set TypingSpeed 90ms

# --- Launch (hidden to skip cold-start latency) ---
Hide
Type "music"
Enter
Sleep 4s
Show

# --- Beat 1: Playlists — filter to "Sleep", open it, play track 2 (Nude) ---
Type "2"
Sleep 1800ms
Type "/"
Sleep 500ms
Type "sleep"
Sleep 1500ms
Enter
Sleep 1000ms
Enter
Sleep 2800ms
Down
Sleep 1200ms
Enter

# --- Beat 2: Now Playing (Nude playing; full Up Next list) ---
Sleep 4000ms

# --- Beat 3: Controls in use ---
Left
Sleep 1500ms
Enter
Sleep 1500ms
Down
Sleep 800ms
Enter
Sleep 1500ms
Down
Sleep 800ms
Enter
Sleep 1500ms
Right
Sleep 1500ms

# --- Beat 4: Speakers + EQ ---
Type "3"
Sleep 3000ms          # wait for the async AirPlay enumeration to render
Down 2                # MacBook -> Sonos arc -> Kitchen (first inactive output)
Sleep 1000ms
Enter                 # select Kitchen into the active group
Sleep 3000ms          # hold on the speaker list + EQ block — the final shot

# No Visualizer step: it's a non-terminal visual (renders in Music.app's own
# window), so toggling it can't appear in a terminal recording. The committed
# media/demo.gif is this flow's output, trimmed to end on the speaker/EQ view.

# --- End ---
Type "q"
Sleep 1s
