import ArgumentParser
import Foundation

struct Play: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Play or resume music.")

    @Argument(help: "Playlist name, result index, or 'shuffle'") var args: [String] = []
    @Option(name: .long, help: "Playlist name") var playlist: String?
    @Option(name: .long, help: "Song name") var song: String?
    @Option(name: .long, help: "Artist name") var artist: String?
    @Flag(name: .long, help: "Output JSON") var json = false
    @Flag(name: [.customShort("v"), .customLong("verbose")], help: "Show diagnostic output") var verboseFlag = false
    @Flag(name: .long, help: "Skip speaker wake cycle") var noWake = false

    func run() throws {
        Music.verbose = verboseFlag
        Music.isJSON = json
        Music.noWake = noWake
        let backend = AppleScriptBackend()

        // Existing flag-based behavior takes priority
        if let playlist = playlist {
            wakeInheritedSpeakers(backend: backend)
            _ = try syncRun {
                try await backend.runMusic("""
                    set shuffle enabled to true
                    play playlist "\(playlist)"
                """)
            }
            showNowPlaying(json: json, waitForPlay: true)
            return
        }

        if let song = song {
            wakeInheritedSpeakers(backend: backend)
            let artistFilter = artist.map { " and artist contains \"\($0)\"" } ?? ""
            let result = try syncRun {
                try await backend.runMusic("""
                    set results to (every track of playlist "Library" whose name contains "\(song)"\(artistFilter))
                    if (count of results) > 0 then
                        play item 1 of results
                        return "OK"
                    else
                        return "NOT_FOUND"
                    end if
                """)
            }
            if result.trimmingCharacters(in: .whitespacesAndNewlines) == "NOT_FOUND" {
                print("No tracks found matching '\(song)'")
                throw ExitCode.failure
            }
            showNowPlaying(json: json, waitForPlay: true)
            return
        }

        // Smart positional args
        if !args.isEmpty {
            // Single integer → play from cache
            if args.count == 1, let index = Int(args[0]) {
                wakeInheritedSpeakers(backend: backend)
                let cache = ResultCache()
                let song = try cache.lookupSong(index: index)
                let escapedTitle = song.title.replacingOccurrences(of: "\"", with: "\\\"")
                let escapedArtist = song.artist.replacingOccurrences(of: "\"", with: "\\\"")
                let result = try syncRun {
                    try await backend.runMusic("""
                        set results to (every track of playlist "Library" whose name is "\(escapedTitle)" and artist is "\(escapedArtist)")
                        if (count of results) = 0 then
                            set results to (every track of playlist "Library" whose name contains "\(escapedTitle)" and artist contains "\(escapedArtist)")
                        end if
                        if (count of results) > 0 then
                            play item 1 of results
                            return "OK"
                        else
                            return "NOT_FOUND"
                        end if
                    """)
                }
                if result.trimmingCharacters(in: .whitespacesAndNewlines) == "NOT_FOUND" {
                    print("'\(song.title)' not in library. Run: music add \(index)")
                    throw ExitCode.failure
                }
                showNowPlaying(json: json, waitForPlay: true)
                return
            }

            // Check for trailing "shuffle" keyword
            let hasShuffle = args.last?.lowercased() == "shuffle"
            var remaining = hasShuffle ? Array(args.dropLast()) : args

            // Extract volume (last arg if it's a number 0-100)
            var speakerVolume: Int? = nil
            if remaining.count >= 2, let vol = Int(remaining.last!), (0...100).contains(vol) {
                speakerVolume = vol
                remaining = Array(remaining.dropLast())
            }

            // Try to match a speaker name from the args (longest match wins)
            var matchedSpeaker: String? = nil
            var playlistName: String
            let joinedLower = remaining.joined(separator: " ").lowercased()

            if let devices = try? fetchSpeakerDevices() {
                let deviceNames = devices.map { $0["name"] as! String }
                var bestLen = 0
                for devName in deviceNames {
                    let devLower = devName.lowercased()
                    if joinedLower.contains(devLower) && devLower.count > bestLen {
                        matchedSpeaker = devName
                        bestLen = devLower.count
                    }
                }
                if let speaker = matchedSpeaker {
                    verbose("matched speaker \"\(speaker)\" from args")
                    // Remove speaker name from the joined string to get playlist name
                    let cleaned = joinedLower.replacingOccurrences(of: speaker.lowercased(), with: "")
                        .trimmingCharacters(in: .whitespaces)
                    playlistName = cleaned.isEmpty ? "" : cleaned
                    // Restore original case from args for the playlist name
                    if !cleaned.isEmpty {
                        // Re-join args without the speaker words
                        let speakerWords = Set(speaker.lowercased().split(separator: " ").map(String.init))
                        let playlistArgs = remaining.filter { !speakerWords.contains($0.lowercased()) }
                        playlistName = playlistArgs.joined(separator: " ")
                    }
                } else {
                    playlistName = remaining.joined(separator: " ")
                }
            } else {
                playlistName = remaining.joined(separator: " ")
            }

            // Route to speaker with wake cycle
            if let speaker = matchedSpeaker {
                if !Music.noWake {
                    let results = withStatus("Waking speakers...") {
                        wakeSpeakers([speaker], backend: backend)
                    }
                    for r in results {
                        if r.verifiedSelected {
                            print("Woke \(r.name).")
                        } else {
                            print("\(r.name): wake cycle completed but verification uncertain.")
                        }
                    }
                } else {
                    _ = try syncRun {
                        try await backend.runMusic("set selected of AirPlay device \"\(speaker)\" to true")
                    }
                }
                // Set volume if specified
                if let vol = speakerVolume {
                    _ = try syncRun {
                        try await backend.runMusic("set sound volume of AirPlay device \"\(speaker)\" to \(vol)")
                    }
                    print("\(speaker) [\(vol)]")
                }
            }

            if matchedSpeaker == nil {
                wakeInheritedSpeakers(backend: backend)
            }

            if hasShuffle {
                _ = try syncRun {
                    try await backend.runMusic("set shuffle enabled to true")
                }
            }

            if !playlistName.isEmpty {
                _ = try syncRun {
                    try await backend.runMusic("play playlist \"\(playlistName)\"")
                }
            } else if matchedSpeaker != nil {
                // Speaker routed but no playlist specified — just resume
                _ = try syncRun {
                    try await backend.runMusic("play")
                }
            } else {
                // No speaker, no playlist — shouldn't happen but resume
                _ = try syncRun {
                    try await backend.runMusic("play")
                }
            }
            showNowPlaying(json: json, waitForPlay: true)
            return
        }

        // No args → resume
        wakeInheritedSpeakers(backend: backend)
        _ = try syncRun {
            try await backend.runMusic("play")
        }
        showNowPlaying(json: json, waitForPlay: true)
    }
}

/// Wake any non-local AirPlay speakers that are already selected from a previous session.
private func wakeInheritedSpeakers(backend: AppleScriptBackend) {
    guard !Music.noWake else { return }
    guard let devices = try? fetchSpeakerDevices() else { return }
    let nonLocal = devices.filter {
        ($0["selected"] as? Bool == true) && ($0["kind"] as? String != "computer")
    }
    let names = nonLocal.map { $0["name"] as! String }
    guard !names.isEmpty else { return }
    verbose("inherited AirPlay session detected: \(names.joined(separator: ", "))")
    let results = withStatus("Waking speakers...") {
        wakeSpeakers(names, backend: backend)
    }
    for r in results {
        if r.verifiedSelected {
            verbose("woke \(r.name)")
        } else {
            verbose("\(r.name): wake verification uncertain")
        }
    }
}

struct Pause: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Pause playback.")
    func run() throws {
        let backend = AppleScriptBackend()
        _ = try syncRun { try await backend.runMusic("pause") }
        print("Paused.")
    }
}

struct Skip: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Skip to next track.")
    @Flag(name: .long, help: "Output JSON") var json = false
    func run() throws {
        let backend = AppleScriptBackend()
        _ = try syncRun { try await backend.runMusic("next track") }
        showNowPlaying(json: json, waitForPlay: true)
    }
}

struct Back: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Go to previous track.")
    @Flag(name: .long, help: "Output JSON") var json = false
    func run() throws {
        let backend = AppleScriptBackend()
        _ = try syncRun { try await backend.runMusic("previous track") }
        showNowPlaying(json: json, waitForPlay: true)
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop playback.")
    func run() throws {
        let backend = AppleScriptBackend()
        _ = try syncRun { try await backend.runMusic("stop") }
        print("Stopped.")
    }
}

struct Now: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show what's currently playing.")
    @Flag(name: .long, help: "Output JSON") var json = false
    func run() throws {
        if isBareInvocation(command: "now") && isTTY() {
            runNowPlayingTUI()
            return
        }
        showNowPlaying(json: json)
    }
}

func showNowPlaying(json: Bool = false, waitForPlay: Bool = false) {
    let backend = AppleScriptBackend()
    let stoppedCheck = waitForPlay ? """
                    if state is "stopped" then
                        error "waiting for playback"
                    end if
    """ : """
                    if state is "stopped" then
                        return "STOPPED"
                    end if
    """
    guard let result = try? syncRun({
        try await backend.runMusic("""
            repeat 10 times
                try
                    set state to player state as text
                    \(stoppedCheck)
                    set t to name of current track
                    set a to artist of current track
                    set al to album of current track
                    set d to duration of current track
                    set p to player position
                    set spk to ""
                    set deviceList to every AirPlay device
                    repeat with dev in deviceList
                        if selected of dev then
                            if spk is not "" then set spk to spk & ","
                            set spk to spk & name of dev & ":" & sound volume of dev
                        end if
                    end repeat
                    return t & "|" & a & "|" & al & "|" & (round d) & "|" & (round p) & "|" & state & "|" & spk
                end try
                delay 0.3
            end repeat
            return "LOADING"
        """)
    }) else { return }

    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "STOPPED" {
        print(json ? "{\"state\":\"stopped\"}" : "Nothing playing.")
        return
    }
    let parts = trimmed.split(separator: "|", maxSplits: 6).map(String.init)
    guard parts.count >= 7 else { print("Unexpected output"); return }

    let speakers = parts[6].split(separator: ",").map { pair -> [String: Any] in
        let kv = pair.split(separator: ":", maxSplits: 1)
        return ["name": String(kv[0]), "volume": Int(kv.count > 1 ? String(kv[1]) : "0") ?? 0]
    }

    if json {
        let dict: [String: Any] = [
            "track": parts[0], "artist": parts[1], "album": parts[2],
            "duration": Int(parts[3]) ?? 0, "position": Int(parts[4]) ?? 0,
            "state": parts[5], "speakers": speakers
        ]
        let output = OutputFormat(mode: .json)
        print(output.render(dict))
    } else {
        let spkStr = speakers.map { "\($0["name"]!) (vol: \($0["volume"]!))" }.joined(separator: " | ")
        print("\(parts[0]) — \(parts[1]) [\(parts[2])]")
        if !spkStr.isEmpty { print(spkStr) }
    }
}

struct Shuffle: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Toggle shuffle.")
    @Argument(help: "on or off") var state: String
    func run() throws {
        let backend = AppleScriptBackend()
        let val = state.lowercased() == "on" ? "true" : "false"
        _ = try syncRun { try await backend.runMusic("set shuffle enabled to \(val)") }
        print("Shuffle \(state.lowercased()).")
    }
}

struct Repeat_: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "repeat", abstract: "Set repeat mode.")
    @Argument(help: "off, one, or all") var mode: String
    func run() throws {
        let backend = AppleScriptBackend()
        _ = try syncRun { try await backend.runMusic("set song repeat to \(mode.lowercased())") }
        print("Repeat \(mode.lowercased()).")
    }
}

struct Radio: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start a radio station from the current track.")
    func run() throws {
        let backend = AppleScriptBackend()
        let info = try syncRun {
            try await backend.runMusic("return name of current track & \" — \" & artist of current track")
        }
        let trackInfo = info.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Building radio station from: \(trackInfo) ...")
        startRadioStation()
        print("Started radio station from: \(trackInfo)")
        if isTTY() {
            runNowPlayingTUI()
        }
    }
}

// MARK: - Sync helper for running async from sync ParsableCommand.run()

func syncRun<T>(_ block: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>!
    Task {
        do {
            result = .success(try await block())
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}
