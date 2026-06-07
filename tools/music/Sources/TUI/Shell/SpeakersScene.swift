// tools/music/Sources/TUI/Shell/SpeakersScene.swift
import Foundation

/// One AirPlay output: its name, whether it's in the active group, and its volume.
struct SpeakerRow {
    let name: String
    var active: Bool
    var volume: Int
}

/// Pure mapping from `fetchSpeakerDevices()`'s `[[String:Any]]` to typed rows.
/// Entries missing name/selected/volume are skipped.
func speakerRows(from devices: [[String: Any]]) -> [SpeakerRow] {
    devices.compactMap { d in
        guard let name = d["name"] as? String,
              let active = d["selected"] as? Bool,
              let volume = d["volume"] as? Int else { return nil }
        return SpeakerRow(name: name, active: active, volume: volume)
    }
}

final class SpeakersScene: Scene {
    let id: SceneID = .speakers
    let tabTitle = "Speakers"

    private let backend: AppleScriptBackend
    private var rows: [SpeakerRow] = []
    private var cursor = 0
    private var loaded = false

    init(backend: AppleScriptBackend) { self.backend = backend }

    func tick(snapshot: NowPlayingSnapshot) {
        // One-time load (brief stall on first open; off-main is future polish).
        if !loaded {
            loaded = true
            rows = speakerRows(from: (try? fetchSpeakerDevices()) ?? [])
            if cursor >= rows.count { cursor = max(0, rows.count - 1) }
        }
    }

    func render(frame: ShellFrame, snapshot: NowPlayingSnapshot) -> String {
        var out = ""
        for r in frame.bodyY..<(frame.bodyY + frame.bodyHeight) {
            out += ANSICode.moveTo(row: r, col: 1) + ANSICode.clearLine
        }
        var y = frame.bodyY
        out += ANSICode.moveTo(row: y, col: 3)
        out += "\(ANSICode.bold)\(ANSICode.cyan)AirPlay Outputs\(ANSICode.reset)"
        y += 2

        if rows.isEmpty {
            out += ANSICode.moveTo(row: y, col: 3) + "\(ANSICode.dim)No AirPlay outputs found.\(ANSICode.reset)"
            return out
        }

        let nameW = 18
        let barW = 16
        let bottom = frame.bodyY + frame.bodyHeight - 1
        for (i, row) in rows.enumerated() {
            guard y <= bottom else { break }
            out += ANSICode.moveTo(row: y, col: 3)
            let isCursor = i == cursor
            let marker = isCursor ? "\(ANSICode.cyan)\u{25B8}\(ANSICode.reset)" : " "
            let dot = row.active ? "\(ANSICode.lime)\u{25CF}\(ANSICode.reset)" : "\(ANSICode.dim)\u{25CB}\(ANSICode.reset)"
            let name = truncText(row.name, to: nameW)
            let padName = name + String(repeating: " ", count: max(0, nameW - name.count))
            let nameStr = row.active
                ? "\(ANSICode.brightWhite)\(padName)\(ANSICode.reset)"
                : "\(ANSICode.dim)\(padName)\(ANSICode.reset)"
            let bar = meterBar(value: row.volume, width: barW)
            let vol = String(format: "%3d", row.volume)
            out += "\(marker) \(dot) \(nameStr) \(bar) \(vol)"
            y += 1
        }

        // Hint inside the body.
        if y + 1 <= bottom {
            out += ANSICode.moveTo(row: y + 1, col: 3)
            out += "\(ANSICode.dim)Enter toggle active   \u{2190}\u{2192} volume   Esc back\(ANSICode.reset)"
        }
        return out
    }

    func handle(_ key: KeyPress) -> SceneAction {
        guard !rows.isEmpty else {
            if case .escape = key { return .pop }
            return .none
        }
        switch key {
        case .up:
            cursor = max(0, cursor - 1); return .redraw
        case .down:
            cursor = min(rows.count - 1, cursor + 1); return .redraw
        case .enter:
            rows[cursor].active.toggle()
            setSelected(rows[cursor])
            return .redraw
        case .left:
            rows[cursor].volume = max(0, rows[cursor].volume - 5)
            setVolume(rows[cursor])
            return .redraw
        case .right:
            rows[cursor].volume = min(100, rows[cursor].volume + 5)
            setVolume(rows[cursor])
            return .redraw
        case .escape:
            return .pop
        default:
            return .none
        }
    }

    // MARK: AppleScript (each its own call — never batched, per the -50 rule)

    private func setSelected(_ row: SpeakerRow) {
        let esc = escapeAppleScriptString(row.name)
        _ = try? syncRun { try await self.backend.runMusic("set selected of AirPlay device \"\(esc)\" to \(row.active)") }
    }
    private func setVolume(_ row: SpeakerRow) {
        let esc = escapeAppleScriptString(row.name)
        let v = row.volume
        _ = try? syncRun { try await self.backend.runMusic("set sound volume of AirPlay device \"\(esc)\" to \(v)") }
    }
}
