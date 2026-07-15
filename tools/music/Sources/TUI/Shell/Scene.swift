// tools/music/Sources/TUI/Shell/Scene.swift
import Foundation

/// What a scene asks the shell to do after handling a key.
enum SceneAction: Equatable {
    case none          // key ignored
    case redraw        // state changed; repaint next frame (already continuous, but explicit)
    case push(SceneID) // drill into another scene
    case pop           // go back
    case quit          // exit the shell
}

/// A renderable, interactive surface inside the shell. Implementations draw into
/// the body region the shell hands them (frame.bodyY .. frame.bodyY+bodyHeight-1)
/// and never touch chrome, tabs, or the now-playing bar.
protocol Scene: AnyObject {
    var id: SceneID { get }
    var tabTitle: String { get }

    /// When true, the shell routes every key straight to `handle` without
    /// resolving globals, Tab, or Esc — for raw text entry (filter, search).
    var capturesAllInput: Bool { get }

    /// Called once per loop iteration before render, so the scene can fold the
    /// latest snapshot into its own view state (e.g. clamp a cursor to new row
    /// counts) and drain any background-fetch inboxes. Returns true when the
    /// scene's own state changed in a way the snapshot generation can't see
    /// (drained inbox, async load landed), so the shell repaints. Runs every
    /// iteration regardless of whether the last frame was painted.
    @discardableResult
    func tick(snapshot: NowPlayingSnapshot) -> Bool

    /// Return the ANSI string for the body region only.
    func render(frame: ShellFrame, snapshot: NowPlayingSnapshot) -> String

    /// Handle a scene-local key (globals were already resolved by the shell).
    func handle(_ key: KeyPress) -> SceneAction

    /// Short scene-specific key hints for the shell footer (the shell appends the
    /// global playback keys). Empty by default.
    var footerHint: String { get }

    /// Called right after the shell clears every kitty placement on a scene
    /// switch (`kittyDeletePlacementsEscape`, d=a — placements only, data
    /// stays transmitted). Art-rendering scenes reset their placement-dedup
    /// state (`lastPlaced = nil`) so the next render re-places instead of
    /// assuming a placement the shell just deleted is still on screen. Default
    /// no-op for scenes with no art.
    func artPlacementsInvalidated()
}

extension Scene {
    var capturesAllInput: Bool { false }
    var footerHint: String { "" }
    func artPlacementsInvalidated() {}
}

/// Pure decision: should the shell resolve global/navigation keys for the
/// active scene, or hand everything to the scene? Globals are skipped only when
/// the scene is capturing raw input.
func shellShouldResolveGlobals(forSceneCapturing capturing: Bool) -> Bool {
    !capturing
}
