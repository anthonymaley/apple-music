// Music.app visualizer (Cmd-T) on/off. Like the live EQ state, the scripting
// property `visuals enabled` is severed in current Music builds (set errors
// -10006), so this drives the Window-menu "Visualizer" item via System Events
// and reads on/off from the item's checkmark. Requires Accessibility
// permission. Turning the visualizer ON brings Music to the front — inherent,
// the visualization renders in Music's own window.
//
// NB: the Accessibility-error translation here mirrors EQControl's eqUIRun.
// Kept local to avoid refactoring shipped EQ code; fold into a shared helper
// if a third UI-scripted feature lands.
import Foundation

let visualizerAccessibilityHint = """
Visualizer control drives Music's menu and needs Accessibility permission: \
System Settings → Privacy & Security → Accessibility → enable your terminal app, then retry.
"""

private let visualizerMenuItem = #"menu item "Visualizer" of menu "Window" of menu bar 1"#

/// True when the Visualizer menu item shows a checkmark (✓ = on).
func parseVisualizerMark(_ raw: String) -> Bool {
    raw.trimmingCharacters(in: .whitespacesAndNewlines) == "\u{2713}"
}

private func visualizerUIRun(_ backend: AppleScriptBackend, _ body: String) throws -> String {
    let script = """
        tell application "System Events"
            tell process "Music"
                \(body)
            end tell
        end tell
        """
    do {
        return try syncRun { try await backend.run(script) }
    } catch let error as AppleScriptBackend.ScriptError {
        if case .executionFailed(let msg) = error,
           msg.contains("assistive") || msg.contains("-1719") || msg.contains("-25211") {
            throw AppleScriptBackend.ScriptError.executionFailed(visualizerAccessibilityHint)
        }
        throw error
    }
}

func visualizerStatus(_ backend: AppleScriptBackend) throws -> Bool {
    let raw = try visualizerUIRun(backend, """
        get value of attribute "AXMenuItemMarkChar" of \(visualizerMenuItem)
        """)
    return parseVisualizerMark(raw)
}

/// Idempotent: clicks the menu item only when the current state differs.
func visualizerSetEnabled(_ backend: AppleScriptBackend, _ on: Bool) throws {
    // Read the real state rather than defaulting to false — a swallowed read
    // could otherwise flip the visualizer the wrong way (ask "on" while it is
    // already on → toggles off). A failed read surfaces to the caller.
    let current = try visualizerStatus(backend)
    guard current != on else { return }
    // Turning on: close the Equalizer window first — otherwise it surfaces over
    // the visualizer and steals focus when Music comes forward.
    if on { closeEqualizerWindowIfOpen(backend) }
    _ = try visualizerUIRun(backend, "click \(visualizerMenuItem)")
}
