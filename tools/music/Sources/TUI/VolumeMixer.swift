import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct MixerSpeaker {
    let name: String
    var volume: Int
}

func runVolumeMixer(
    speakers: inout [MixerSpeaker],
    onVolumeChange: (String, Int) -> Void
) {
    let terminal = TerminalState.shared
    terminal.enterRawMode()
    defer { terminal.exitRawMode() }

    var cursor = 0
    var digitBuffer = ""

    let listX = 3
    let levelsX = 36
    let nameW = 22
    let barW = 24

    func render() {
        let frame = ScreenFrame.current()
        let activeCount = speakers.filter { $0.volume > 0 }.count
        let statusText = "\(activeCount) active output\(activeCount == 1 ? "" : "s")"
        let footerText = "\(ANSICode.dim)Controls\(ANSICode.reset)  \(ANSICode.bold)↑↓\(ANSICode.reset) Speaker   \(ANSICode.bold)←→\(ANSICode.reset) Adjust 5%   \(ANSICode.bold)0-9\(ANSICode.reset) Quick Set   \(ANSICode.bold)q\(ANSICode.reset) Quit"

        var out = renderShell(title: "Volume Mixer", status: statusText, footer: footerText)

        // Left pane: speaker list
        for (i, spk) in speakers.enumerated() {
            let row = frame.bodyY + 2 + i
            out += ANSICode.moveTo(row: row, col: listX)
            let pointer = i == cursor ? "\(ANSICode.cyan)▶\(ANSICode.reset)" : " "
            let name = truncText(spk.name, to: 26)
            if i == cursor {
                out += "\(pointer) \(ANSICode.bold)\(name)\(ANSICode.reset)"
            } else {
                out += "\(pointer) \(name)"
            }
        }

        // Right pane: levels
        out += ANSICode.moveTo(row: frame.bodyY, col: levelsX)
        out += "\(ANSICode.bold)Levels\(ANSICode.reset)"
        out += ANSICode.moveTo(row: frame.bodyY + 1, col: levelsX)
        out += "\(ANSICode.dim)\(String(repeating: "─", count: 10))\(ANSICode.reset)"

        for (i, spk) in speakers.enumerated() {
            let row = frame.bodyY + 3 + i
            let active = i == cursor
            out += ANSICode.moveTo(row: row, col: levelsX)

            let name = truncText(spk.name, to: nameW)
            let padded = name.padding(toLength: nameW, withPad: " ", startingAt: 0)
            let bar = meterBar(value: spk.volume, width: barW)
            let pct = String(format: "%3d%%", spk.volume)

            if active {
                out += "\(ANSICode.bold)\(padded)\(ANSICode.reset)  \(bar) \(pct)"
            } else {
                out += "\(ANSICode.dim)\(padded)\(ANSICode.reset)  \(bar) \(ANSICode.dim)\(pct)\(ANSICode.reset)"
            }
        }

        print(out, terminator: "")
        fflush(stdout)
    }

    render()

    while true {
        guard let key = KeyPress.read() else { continue }
        switch key {
        case .up:
            cursor = max(0, cursor - 1)
            digitBuffer = ""
        case .down:
            cursor = min(speakers.count - 1, cursor + 1)
            digitBuffer = ""
        case .left:
            speakers[cursor].volume = max(0, speakers[cursor].volume - 5)
            onVolumeChange(speakers[cursor].name, speakers[cursor].volume)
            digitBuffer = ""
        case .right:
            speakers[cursor].volume = min(100, speakers[cursor].volume + 5)
            onVolumeChange(speakers[cursor].name, speakers[cursor].volume)
            digitBuffer = ""
        case .char(let c) where c.isNumber:
            digitBuffer.append(c)
            if digitBuffer.count >= 2 {
                if let vol = Int(digitBuffer) {
                    speakers[cursor].volume = min(100, max(0, vol))
                    onVolumeChange(speakers[cursor].name, speakers[cursor].volume)
                }
                digitBuffer = ""
            }
        case .char("q"), .escape:
            return
        default:
            digitBuffer = ""
        }
        render()
    }
}
