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
