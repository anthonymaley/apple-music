# Error-Handling Audit — `tools/music/Sources`

**Date:** 2026-06-25
**Scope:** Every `try?`, `try!`, bare `catch {}`, and force-unwrap (`as!`, postfix `!`) in `tools/music/Sources` (~55 Swift files, ~8k LoC). Entry point per request: the AppleScript/UI-scripting backends, then outward through the command and TUI layers.
**Method:** Each occurrence read in the context of its enclosing function and classified against this codebase's platform reality (Music.app scripting is partly severed — see below). Read-only audit; **no code was changed.**
**Classification:** `B` = benign-best-effort · `M` = masks a user-visible failure. Recommendation ∈ {`stderr` (surface the error / non-zero exit / `--json` error object), `fallback` (add or confirm an explicit fallback), `leave`}. Priority: **P1** = silent failure or crash on a *common* path · **P2** = user-visible but edge/rare, or a misleading-but-not-silent cause · **P3** = benign/cosmetic.

> **Resolution (v3.2.2, 2026-06-25):** all 19 masking sites below were fixed. The testable kernels (`OutputFormat` error JSON — which also closed a latent `JSONSerialization` crash on non-JSON types; `AuthManager` corrupt-config detection; `ResultCache.lookupSongs`) are covered by new unit tests; the AppleScript-path surfacing was live-verified by the maintainer. A new always-on `errorOut(...)` channel was added to `StatusReporter`. Suite 151 → 158, clean build.

---

## Executive summary

The codebase is, on the whole, disciplined about errors. Backends **throw and propagate**; the TUI *Scenes* layer routes every user action through a `require(...)`/`StatusToast` helper that turns a swallowed `try?` into a visible footer toast; force-unwraps are nearly all provably non-nil. The masking that exists is **concentrated**, not pervasive.

Two structural facts drive almost every finding:

1. **The masking sites never used the existing `stderr` channel.** A diagnostic stderr channel *does* exist (`StatusReporter.swift`: `verbose()`, `withStatus()`), but the swallowing command paths reported via `print` (stdout) or not at all — so failures either corrupted `--json` output or vanished entirely. The fix adds an always-on `errorOut(...)` to `StatusReporter` and routes the masking sites through it. *(Correction: an earlier draft of this report claimed "no stderr channel anywhere" — that overstated a finding correctly scoped to the three heaviest command files; `StatusReporter` already existed.)*

2. **The masking lives in the CLI quick-picker callbacks and the input side — not the TUI Scenes.** The same logical action (toggle a speaker) is correctly surfaced in `SpeakersScene` (via `require`) but silently swallowed in the bare-`music speaker` quick picker in `SpeakerCommands`. The Scenes layer is the model the command layer should follow.

**Headline (P1):** two sites swallow a user-visible outcome whole — the interactive speaker toggle (`SpeakerCommands:176`) and the post-action "now playing" confirmation (`PlaybackCommands:387`).

**Counts:** ~120 audited sites. **2 P1**, **~16 P2**, remainder benign (P3). Only one genuine crash-risk force-unwrap class (the two REST `as!` casts); all other `as!`/`!`/`try!` are guaranteed non-nil by construction.

### Platform reality used for classification

Music.app's **live EQ/visualizer scripting writes are severed** in current macOS (`set EQ enabled` → −10006, `set current EQ preset` → −1731, `set visuals enabled` → −10006; reads return stale values). The code works around this with Accessibility UI-scripting. Therefore a `try?`/`catch` that tolerates a known-severed scripting call **and has a UI-scripting fallback is benign by design** — those are correctly *not* flagged as masks. A swallow only counts as `M` when the user's requested action is left silently un-done (or mis-done) with no surfaced error and no fallback.

---

## P1 — fix first (silent failure on a common path)

| # | Site | What happens | Class | Rec |
|---|------|--------------|-------|-----|
| 1 | `Commands/SpeakerCommands.swift:176` | `_ = try? syncRun { …set selected… }` — the bare-`music speaker` interactive picker's on/off toggle. A failed AirPlay select (sleeping HomePod, ghost speaker — the *known-flaky* case) leaves the row visually flipped but the device unrouted. User is told it worked. | **M** | **stderr** — return/print a failure and exit non-zero; mirror the `require(...)` pattern the TUI `SpeakersScene:402` already uses for the identical action. |
| 2 | `Commands/PlaybackCommands.swift:387` | `guard let result = try? syncRun({ …now-playing+speakers… }) else { return }` in `showNowPlaying`. The entire read is swallowed → after a successful `play`/`skip`/`pause` the CLI prints **nothing**, and in `--json` mode emits **no object**. Indistinguishable from "nothing happened". | **M** | **stderr** — on read failure, emit an error to stderr (and an error object under `--json`); do not return silently. |

---

## P2 — should fix (user-visible but edge, or misleading cause)

### Interactive write callbacks swallowed (same family as P1 #1)

| Site | What happens | Class | Rec |
|------|--------------|-------|-----|
| `Commands/SpeakerCommands.swift:183` | `_ = try? syncRun { …set sound volume… }` — picker volume adjust. Displayed `vol: N` can diverge from the device on a failed write. | M | stderr |
| `Commands/VolumeCommands.swift:20` | `_ = try? syncRun { …set sound volume… }` — interactive volume *mixer* write. Mixer shows the new level; a failed AirPlay write is silent. | M | stderr |
| `TUI/Shell/PlaylistsScene.swift:352` | `_ = try? syncRun { set shuffle enabled to … }` before play. The `play playlist` itself **is** checked (line 353), so a track still plays — but possibly in the wrong shuffle state, silently. The lone residual `_ = try?` in the otherwise-clean Scenes layer. | M | stderr (toast) |

### Reset / verification reports unconfirmed success

| Site | What happens | Class | Rec |
|------|--------------|-------|-----|
| `Commands/SpeakerCommands.swift:283` | `guard let devices = try? fetchSpeakerDevices() else { verbose(…); return [] }` — if the probe throws, reset returns `[]` and the caller prints "No active AirPlay speakers to reset." A probe *failure* is reported as "nothing to reset." (`verbose` only shows under `-v`.) | M | stderr |
| `Commands/SpeakerCommands.swift:343` | `let after = (try? fetchSpeakerDevices()) ?? []` — post-reset verification re-fetch. On failure `after` is empty, and line 346 then marks every speaker `reselected: true` — reports success it could not confirm. | M | fallback (treat empty verify as "unverified", not "success") |

### Auth / cause conflation (misleading, not silent)

| Site | What happens | Class | Rec |
|------|--------------|-------|-----|
| `Commands/PlaybackCommands.swift:262–263` | `guard let devToken = try? auth.requireDeveloperToken(), let userToken = try? auth.requireUserToken() else { … return false }` — catalog-add fallback. Conflates *tokens broken/expired* with *song genuinely not found*; the caller prints "No local or catalog tracks found". A user with broken auth is told the song doesn't exist. | M | stderr (distinguish auth failure from not-found) |
| `Commands/PlaybackCommands.swift:292–293` | Same pattern for the song-ID play path → "Could not play Apple Music song id X". | M | stderr |
| `Auth/AuthManager.swift:17` | `try? JSONDecoder().decode(AuthConfig.self, …)` — a **corrupt** `config.json` collapses to nil, indistinguishable from "no config". Downstream throws `configNotFound`, so the user sees "not configured" instead of "config is malformed". (Auth still hard-errors; it does **not** silently proceed token-less.) | M | stderr (report parse error distinctly) |

### Input-side drops (fewer results than requested, under a success message)

| Site | What happens | Class | Rec |
|------|--------------|-------|-----|
| `Commands/PlaylistCommands.swift:196` | `if let song = try? cache.lookupSong(index: idx) …` in `playlist create`. `lookupSong` throws on missing cache / out-of-range index; swallowed → `playlist create X 3 9` silently drops bad indices and builds a shorter playlist than asked. | M | stderr (report dropped indices) |
| `Commands/PlaylistCommands.swift:258` | Same in `playlist add` → "Added N track(s)" with N possibly < requested. | M | stderr |
| `Commands/RemoveCommand.swift:27` | `let check = try? syncRun { … }` in `deleteTrack`. A real AppleScript/permission error collapses to "not DELETED", so `remove <playlist>` prints "'X' not found." for an op that actually errored. | M | stderr |

### Routing degraded silently

| Site | What happens | Class | Rec |
|------|--------------|-------|-----|
| `Commands/PlaybackCommands.swift:126` | `(try? fetchSpeakerDevices())?.compactMap {…} ?? []` feeds `PlayParser` the known speaker names. On throw → empty list → the user's speaker words get parsed into the query/playlist instead of as routing targets. A requested route silently degrades to wrong target / not-found. | M | fallback (or surface that device enumeration failed) |

### Read-default mis-behaviour

| Site | What happens | Class | Rec |
|------|--------------|-------|-----|
| `Backends/VisualizerControl.swift:53` | `let current = (try? visualizerStatus(backend)) ?? false` — idempotent guard. If the *status read* fails and defaults to `false` while the visualizer is actually on, asking to turn it "on" clicks anyway and toggles it **off** (wrong direction). The click itself (line 58) is a real `try`. | M | stderr (don't act on an unread state) |
| `Backends/LibraryLookup.swift:24` | `guard let result = try? syncRun({…}) else { return false }` — library-duplicate fallback. The script error text is discarded behind a bare `false`; whether the user is misled depends on the caller surfacing it. | M | stderr (preserve the error) |

### Force-cast crash risk (the only real one)

| Site | What happens | Class | Rec |
|------|--------------|-------|-----|
| `Backends/RESTAPIBackend.swift:29` | `(response as! HTTPURLResponse).statusCode` in `get`. For `https://` via `URLSession` the response is effectively always `HTTPURLResponse`, so it won't crash on normal input — but a non-HTTP/proxy edge case crashes the CLI instead of surfacing an `APIError`. | M | stderr (`guard let … as? HTTPURLResponse else { throw … }`) |
| `Backends/RESTAPIBackend.swift:45` | Identical force-cast in `post`. | M | stderr |

### `--json` output integrity

| Site | What happens | Class | Rec |
|------|--------------|-------|-----|
| `Models/OutputFormat.swift:39` | `try? JSONSerialization.data(…)` in `renderJSON` returns `"{}"` on failure. A non-serializable value silently yields empty JSON to a machine consumer. | M | fallback (emit an error JSON / note to stderr) |

---

## Benign (P3) — verified safe, no change recommended

These are listed so the audit is complete; each was confirmed benign in context.

### Backends
| Site | Why benign |
|------|-----------|
| `EQControl.swift:107` | Closed-window EQ-read *fallback*; yields a non-crashing snapshot, not a requested write. |
| `EQControl.swift:176` | `try?` closing the Equalizer window before the visualizer — cosmetic housekeeping, documented best-effort. |
| `LibraryLookup.swift:44` | Sync-poll count read; `-1` is the explicit "not yet" sentinel the bounded loop is built around. |
| `PlaybackModes.swift:13,22` | `allCases.firstIndex(of: self)!` — `self` is always a member of its own `allCases`; statically non-nil. |
| `MusicUIScripting.swift:19`, `EQControl.swift:67`, `VisualizerControl.swift:35` | `catch let … as ScriptError` blocks that translate Accessibility-denial codes into actionable hints and **re-throw** — non-swallowing. No empty catch bodies exist anywhere in scope. |

### Command layer (force-unwraps & cache writes)
| Site(s) | Why benign |
|---------|-----------|
| `SpeakerCommands.swift:168,170,175,181,259–260,293,394`; `VolumeCommands.swift:17,29,34`; `PlaylistCommands.swift:116–119,129` | `as!`/`!` on dictionaries the code **just built** (`parseSpeakerDeviceBlocks` / the playlist row dict) with always-present, fixed-type keys. Cannot be nil on backend input. |
| `VolumeCommands.swift:91` | `args.last!` reached only when `args.count >= 2` (the `count==1` branch returns earlier). |
| `PlaybackCommands.swift:428,546,552` | `kv[0]` (map runs only for non-empty tokens); `syncRun`'s `Result` IUO is assigned before `semaphore.signal()` and read after `wait()`. |
| `PlaybackCommands.swift:284,303` | `try! Task.sleep(…)` on a literal duration in a non-cancelled sync context — only throws on cancellation. |
| `SpeakerCommands.swift:145,304,321,332,195,203,262,369`; cache `writeSongs`/`writeSpeakers` across `PlaylistCommands`, `DiscoveryCommands`, `SearchCommand`, `HistoryCommands` | Result-cache write-throughs (failure only affects later *index-chaining*, not the current output) and per-device reset tolerances that are re-verified and reported downstream (the "Lost X" safety net at `SpeakerCommands:343–347`). |
| `PlaylistCommands.swift:46,85,302,308,450`; `DiscoveryCommands.swift:22`; `AuthCommands.swift:53`; `EQCommands.swift:51,95`; `RemoveCommand.swift:83` | REST→AppleScript fallback gates (real alternate paths), guarded unwraps, the status command's intended works/doesn't boolean, sparkline enrichment, and the dead outer `try?` in bulk remove. |

### TUI / Models / Auth
| Site(s) | Why benign |
|---------|-----------|
| `NowPlayingTUI.swift:40,70,116,194,239,317`; `PlaybackContext.swift:41`; `NowPlayingScene.swift:137`; `SpeakersScene.swift:129,133,134`; `PlaylistDataSources.swift:31–41,75,114,144,199,219` | Periodic **poll/render** reads with self-healing fallbacks to stale/empty state, and cache persistence — all refresh on the next tick; several documented in comments. |
| `NowPlayingScene.swift:498,506,514,521`; `SpeakersScene.swift:402,413,425,438,455,458,460`; `PlaylistsScene.swift:353`; `AppQueue.swift:66,73,116`; `NowPlayingTUI.swift:317` | User actions wrapped in `require((try? …) != nil, "Couldn't …")` → visible toast. **This is the model the command layer should adopt.** |
| `Router.swift:15` | `stack.last!` — nav stack invariantly non-empty (init `[root]`; `pop()` guards `count>1`). |
| `AuthPage.swift:43` | `catch(e)` inside an embedded **JavaScript** string that surfaces the error in the browser — not Swift; false positive. |
| `AuthPage.swift:164` | `try?` removing a temp server script after auth — leftover temp file at worst. |
| `JWTGenerator.swift`, `ResultCache.swift` | JWT signing and cache I/O propagate all errors via `throws` — no swallows. |

---

## Recommended order of work

1. **Add an always-on stderr error reporter** — `StatusReporter` already has `verbose()`/`withStatus()`; add `errorOut(...)` (plus an `--json` error-object path). Nearly every `M` fix below depends on having somewhere to report into. *(Foundational — do first.)*
2. **P1 #1 & #2** — make the speaker quick-picker toggle and `showNowPlaying` surface failure (copy the Scenes `require` pattern). *Transformative — touches user-facing CLI output; wants tests + review.*
3. **P2 interactive writes & reset verification** (`SpeakerCommands:183,283,343`, `VolumeCommands:20`, `PlaylistsScene:352`).
4. **P2 cause-conflation** (`PlaybackCommands:262/292`, `AuthManager:17`) — distinguish auth failure from not-found/not-configured.
5. **P2 input-side drops** (`PlaylistCommands:196,258`, `RemoveCommand:27`) — report dropped/failed items.
6. **P2 REST `as!` casts** (`RESTAPIBackend:29,45`) — convert to `guard let … as?`. *Mechanical, low-risk.*
7. **P2 remainder** (`PlaybackCommands:126`, `VisualizerControl:53`, `LibraryLookup:24`, `OutputFormat:39`).

> **Blast radius:** every recommendation above changes runtime behaviour (output, exit codes, error surfacing) — all are **transformative / review-required**, and the project's "build-green ≠ live-verified" rule applies: anything touching AppleScript/Music.app/Accessibility paths must be confirmed live, not just by the unit suite. None of the fixes are pure additive/no-risk.

## Coverage & caveats

- **Covered:** all `*.swift` under `Backends/`, `Commands/`, `TUI/` (incl. `TUI/Shell/`), `Models/`, `Auth/`.
- `AppleScriptBackend.swift` contains **zero** of these patterns — it throws cleanly; the swallowing is all at the call sites, which is why `Commands/` dominates.
- Force-unwrap detection used `as!`, `try!`, and postfix `!` (excluding `!=` / leading negation), each then read in context. The only crash-risk class found is the two REST `as!` casts.
- This is a static reading. "Masks a user-visible failure" is judged from code paths and exit/print behaviour, **not** observed at runtime — confirm the P1/P2 fixes live against a real Music.app + AirPlay setup before considering them done.
