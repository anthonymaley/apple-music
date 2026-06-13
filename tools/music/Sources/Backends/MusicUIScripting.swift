// Shared helper for the features that must drive Music through System Events
// because their scripting writes are severed in current Music builds (EQ live
// state, the visualizer, Genius Shuffle). Translates an Accessibility denial
// into an actionable message.
//
// EQControl and VisualizerControl predate this and keep their own inline copies;
// fold them in here if they're next touched.
import Foundation

let musicUIAccessibilityHint = """
This control drives Music's menus and needs Accessibility permission: \
System Settings → Privacy & Security → Accessibility → enable your terminal app, then retry.
"""

func runMusicUIScript(_ backend: AppleScriptBackend, _ script: String,
                      hint: String = musicUIAccessibilityHint) throws -> String {
    do {
        return try syncRun { try await backend.run(script) }
    } catch let error as AppleScriptBackend.ScriptError {
        if case .executionFailed(let msg) = error,
           msg.contains("assistive") || msg.contains("-1719") || msg.contains("-25211") {
            throw AppleScriptBackend.ScriptError.executionFailed(hint)
        }
        throw error
    }
}
