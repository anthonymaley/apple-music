---
name: speaker
description: "Switch or manage AirPlay speakers. Usage: /music:speaker kitchen, /music:speaker airpods, /music:speaker add bedroom, /music:speaker remove kitchen, /music:speaker list"
argument-hint: "[add|remove] <speaker-name> or airpods or list"
allowed-tools: Bash
---

The user wants to manage their AirPlay speakers. Their request: "$ARGUMENTS"

Run the appropriate osascript command(s) based on what they asked for. Here's how to interpret the argument:

- **"list"** or empty: List all AirPlay devices with their selected/volume status
- **"airpods"**: Discover devices, find the one with "AirPods" in the name, deselect all others, select it
- **"add <name>"**: Select the named device (without deselecting others) — adds to group
- **"remove <name>"**: Deselect the named device — removes from group
- **Just a speaker name** (e.g. "kitchen", "living room"): Deselect all, select only that speaker — switches to it exclusively

After the action, show which speakers are now active with their volumes. Keep it to one line.

Use `osascript -e '...'` for all commands. Speaker names are case-insensitive in the user's input but case-sensitive in AppleScript — discover devices first and match fuzzy.

Split AirPlay routing and playback into separate osascript calls to avoid Parameter error (-50).
