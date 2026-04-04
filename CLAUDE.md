# Apple Music

Claude Code plugin for controlling Apple Music, AirPlay speakers, and AirPods on macOS.

## Commit Rules

- Always push after committing.

## Version Strategy

Use semver in all three locations (keep in sync):
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → `metadata.version`
- `.claude-plugin/marketplace.json` → `plugins[0].version`

## Project Structure

```
skills/music/SKILL.md          # conversational skill (complex requests)
commands/                      # slash commands (14 quick controls)
scripts/statusline.sh          # status line script (now playing)
.claude-plugin/                # plugin.json and marketplace.json
tools/music/                   # Swift CLI source
```
