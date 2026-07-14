// Real cover art for the Library/Playlists hero panes. Album artwork URLs are
// stable {w}x{h} CDN templates; playlist artwork URLs are pre-signed and expire
// in 24h (both live-probed 2026-07-14) — so bytes are cached on disk forever,
// URLs never are. Rendering reuses artworkToAscii (chafa half-blocks, mono
// fallback). Every failure degrades silently to the caller's gradient
// placeholder; a per-session negative cache stops retry loops.
import Foundation

final class ArtworkStore {
    /// {w}x{h} substitution for album CDN templates; pre-signed playlist URLs
    /// contain no placeholder and pass through verbatim.
    static func resolveURL(_ template: String, width: Int, height: Int) -> String {
        template.replacingOccurrences(of: "{w}x{h}", with: "\(width)x\(height)")
    }

    /// Filesystem-safe cache key from a REST resource id.
    static func cacheKey(_ raw: String) -> String {
        String(raw.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}
