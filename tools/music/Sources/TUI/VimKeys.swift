// tools/music/Sources/TUI/VimKeys.swift
// Vim-style navigation aliases. Applied by each scene at the top of handle():
// list scenes pass listScene: true and get the full set; the Now tab passes
// false so its own l (love) and g/G (Genius) bindings keep working.
func vimAlias(_ key: KeyPress, listScene: Bool) -> KeyPress {
    switch key {
    case .char("j"): return .down
    case .char("k"): return .up
    case .char("h"): return .left
    case .char("\u{04}"): return .pageDown   // ctrl-d
    case .char("\u{15}"): return .pageUp     // ctrl-u
    case .char("l") where listScene: return .right
    case .char("G") where listScene: return .end
    case .char("g") where listScene: return .home
    default: return key
    }
}
