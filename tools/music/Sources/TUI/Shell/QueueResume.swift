// tools/music/Sources/TUI/Shell/QueueResume.swift
//
// Pure foundation for queue resume-across-restart. See
// docs/plans/2026-07-16-queue-resume-design.md for the full design. This file is
// deliberately inert: nothing here is called from AppQueueStore, the poller, the
// scenes, or Shell yet. Wiring is a follow-up task.
import Foundation

/// The on-disk shape of a saved queue: the whole in-memory `AppQueue`, verbatim,
/// plus an **anchor** — the identity of the track that was current when saved.
/// The anchor is what `queueMatches` uses on restore to decide adopt-vs-discard;
/// it's kept separate from `AppQueue` itself because a persistent ID (and the
/// save-time name/artist fallback) has no meaning to the in-memory queue, only to
/// the restore guard.
struct PersistedQueue: Codable, Equatable {
    let queue: AppQueue
    /// Apple's stable id (`persistent id of current track`) for the track that
    /// was current at save time. Can be nil when unreadable (the macOS 26 -1728
    /// bug on streamed tracks; album/playlist tracks are library tracks so this
    /// normally reads fine) — name+artist below is always stored as a fallback.
    let anchorPersistentID: String?
    let anchorName: String
    let anchorArtist: String

    /// The saved queue, ready to hand to `AppQueueStore.set`.
    func toAppQueue() -> AppQueue { queue }
}

/// Case/whitespace-insensitive identity compare for the name+artist fallback.
/// Trims outer whitespace and collapses internal runs so "A  Tribe  Called Quest"
/// matches "a tribe called quest".
private func namesMatch(_ a: String, _ b: String) -> Bool {
    func normalize(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    return normalize(a) == normalize(b)
}

/// Does the currently-playing track match the saved queue's current entry?
///
/// Two identity sources are reconciled here: `saved.anchorPersistentID` (captured
/// at save time, lives only on `PersistedQueue`) is authoritative for the
/// persistent-ID check; `saved.queue.tracks[currentIndex - 1]` — the saved
/// queue's own record of its current track — supplies the name+artist fallback,
/// since `TrackListEntry` carries no persistent ID of its own. Persistent ID wins
/// whenever BOTH sides have one, even if names happen to match (two different
/// occurrences of the same title must not be treated as the same track — the mpv
/// index-keyed-resume lesson). Otherwise falls back to name+artist. Pure — no I/O.
func queueMatches(playingPersistentID: String?, playingName: String, playingArtist: String,
                   saved: PersistedQueue) -> Bool {
    let q = saved.queue
    guard q.currentIndex >= 1, q.currentIndex <= q.tracks.count else { return false }
    let savedCurrent = q.tracks[q.currentIndex - 1]

    if let playingID = playingPersistentID, let savedID = saved.anchorPersistentID {
        return playingID == savedID
    }

    return namesMatch(playingName, savedCurrent.name) && namesMatch(playingArtist, savedCurrent.artist)
}

/// Persists the app-owned queue to `~/.config/music/queue.json`, mirroring
/// `StationStore`'s pattern: injectable path for tests, atomic write,
/// create-dir-if-needed, corrupt/missing file reads as absent rather than error.
///
/// No in-memory cache (unlike `StationStore`, which serves many reads/writes per
/// session for a UI list). `QueueStore` is read once at TUI startup and written
/// only at the queue's own mutation points (a handful of times a session) — a
/// disk read each time is cheap here and avoids a cache that could go stale
/// relative to a file another process/instance wrote.
final class QueueStore {
    private let path: String

    init(path: String = NSString(string: "~/.config/music/queue.json").expandingTildeInPath) {
        self.path = path
    }

    func save(_ q: PersistedQueue) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(q)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Absent or corrupt file reads as nil — resume is a convenience, never a
    /// reason to error at the user.
    func load() -> PersistedQueue? {
        guard let data = FileManager.default.contents(atPath: path),
              let q = try? JSONDecoder().decode(PersistedQueue.self, from: data)
        else { return nil }
        return q
    }

    /// No-op if the file doesn't exist.
    func clear() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
