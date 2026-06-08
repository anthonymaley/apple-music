// tools/music/Sources/TUI/Shell/GlobalKeymap.swift
import Foundation

/// Actions the shell handles in every scene, before delegating scene-local keys.
enum GlobalAction: Equatable {
    case playPause, volumeUp, volumeDown, next, prev, shuffle
    case switchScene(Int)   // 1-based index into the visible scene tabs
    case quit
}

/// Pure mapping from a keypress to a global action, or nil if the key is not a
/// global (the shell then delegates it to the active scene). Navigation keys
/// (Tab, Esc) are handled directly by the shell loop, not here.
func resolveGlobalKey(_ key: KeyPress) -> GlobalAction? {
    switch key {
    case .space: return .playPause
    case .char("+"), .char("="): return .volumeUp
    case .char("-"): return .volumeDown
    case .char(">"), .char("."), .f9: return .next
    case .char("<"), .char(","), .f7: return .prev
    case .char("z"), .char("r"): return .shuffle   // 'r' (was radio) now also shuffles
    case .char("q"): return .quit
    case .char(let c) where c.isNumber:
        guard let n = c.wholeNumberValue, n >= 1 else { return nil }
        return .switchScene(n)
    default:
        return nil
    }
}
