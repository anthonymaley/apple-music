---
name: stop
description: Stop Apple Music playback
disable-model-invocation: true
---

!`osascript -e 'tell application "Music" to stop' 2>/dev/null && echo "■ Stopped" || echo "Could not stop"`
