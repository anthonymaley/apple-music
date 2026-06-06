import Foundation

/// Escapes a string for safe interpolation inside an AppleScript double-quoted
/// string literal. Backslash must be escaped first, then the double-quote —
/// otherwise the backslashes introduced for quotes would themselves be doubled.
///
/// Names containing `\` (e.g. a playlist named `AC\DC`) or `"` previously
/// corrupted the generated script or mis-targeted the query; route every
/// user/catalog-supplied value through here before interpolation.
func escapeAppleScriptString(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
