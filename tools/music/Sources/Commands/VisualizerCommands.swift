import ArgumentParser
import Foundation

struct Visualizer: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "visualizer",
        abstract: "Toggle Music's on-screen visualizer (the Cmd-T visuals).")
    @Argument(help: "'on', 'off', or empty for status") var args: [String] = []
    @Flag(name: .long, help: "Output JSON") var json = false

    func run() throws {
        let backend = AppleScriptBackend()
        switch args.joined(separator: " ").lowercased() {
        case "":
            let on = try visualizerStatus(backend)
            print(json ? "{\"on\":\(on)}" : "Visualizer \(on ? "on" : "off")")
        case "on":
            try visualizerSetEnabled(backend, true)
            print(json ? "{\"ok\":true,\"on\":true}" : "Visualizer on")
        case "off":
            try visualizerSetEnabled(backend, false)
            print(json ? "{\"ok\":true,\"on\":false}" : "Visualizer off")
        default:
            throw ValidationError("Usage: music visualizer [on|off]")
        }
    }
}
