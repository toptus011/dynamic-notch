// MusicMonitor.swift – co gra w Apple Music i Spotify
//
// Od macOS 15.4 Apple zablokował innym programom ogólny dostęp do informacji
// „Teraz odtwarzane”, dlatego korzystamy z powiadomień, które oba odtwarzacze
// rozgłaszają same, oraz z AppleScript (okładka, pozycja, sterowanie).
// Zapytania do odtwarzaczy idą przez osobny proces (osascript) w tle – gdy odtwarzacz
// się zatnie, wcięcie działa dalej.

import Cocoa

struct NowPlaying: Equatable {
    var player: Player
    var title: String
    var artist: String
    var playing: Bool
    var duration: Double?      // sekundy
    var position: Double?      // sekundy – w chwili `positionAt`
    var positionAt: Date?
    var artwork: NSImage?
    var tint: NSColor?         // kolor korektora – wyrazisty odcień okładki

    enum Player: String {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var appName: String { self == .music ? "Music" : "Spotify" }
        var displayName: String { self == .music ? "Muzyka" : "Spotify" }
    }

    /// Bieżąca pozycja wyliczona na żywo (bez ciągłego pytania odtwarzacza).
    func livePosition(at now: Date) -> Double {
        guard let position else { return 0 }
        guard playing, let at = positionAt else { return position }
        let value = position + now.timeIntervalSince(at)
        if let duration { return min(value, duration) }
        return value
    }
}

final class MusicMonitor {

    var onChange: ((NowPlaying?) -> Void)?
    private(set) var current: NowPlaying?
    private var positionTimer: Timer?
    private let queue = DispatchQueue(label: "pl.bulka.dynamicnotch.music", qos: .userInitiated)

    init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(musicNote(_:)),
                           name: Notification.Name("com.apple.Music.playerInfo"), object: nil)
        center.addObserver(self, selector: #selector(spotifyNote(_:)),
                           name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        // Jeżeli coś już gra w chwili uruchomienia – zapytaj odtwarzacz.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.queryRunningPlayers() }
    }

    // MARK: - Powiadomienia odtwarzaczy

    @objc private func musicNote(_ note: Notification) {
        handle(note.userInfo, player: .music, durationKey: "Total Time")
    }

    @objc private func spotifyNote(_ note: Notification) {
        handle(note.userInfo, player: .spotify, durationKey: "Duration")
    }

    private func handle(_ info: [AnyHashable: Any]?, player: NowPlaying.Player, durationKey: String) {
        guard let info else { return }
        let state = (info["Player State"] as? String ?? "").lowercased()
        if state == "stopped" || state.isEmpty {
            if current?.player == player { update(nil) }
            return
        }
        let title = info["Name"] as? String ?? current?.title ?? ""
        let artist = info["Artist"] as? String ?? ""
        let duration = (info[durationKey] as? NSNumber).map { $0.doubleValue / 1000 }   // milisekundy

        let sameTrack = current?.player == player && current?.title == title && current?.artist == artist
        let playing = state == "playing"
        var next = NowPlaying(player: player, title: title, artist: artist, playing: playing,
                              duration: duration,
                              position: sameTrack ? current?.livePosition(at: Date()) : 0,
                              positionAt: Date(),
                              artwork: sameTrack ? current?.artwork : nil,
                              tint: sameTrack ? current?.tint : nil)
        if let position = info["Playback Position"] as? NSNumber {
            next.position = position.doubleValue
            next.positionAt = Date()
        }
        update(next)
        if !sameTrack {
            loadArtwork(for: player, title: title)
            refreshPosition()
        }
    }

    private func update(_ value: NowPlaying?) {
        guard value != current else { return }
        current = value
        onChange?(value)
    }

    // MARK: - Stan przy uruchomieniu

    private func queryRunningPlayers() {
        for player in [NowPlaying.Player.music, .spotify] where isRunning(player) {
            let source = """
            tell application "\(player.appName)"
                if player state is playing then
                    return (name of current track) & linefeed & (artist of current track) & linefeed & ((duration of current track) as text)
                end if
            end tell
            """
            runAsync(source) { [weak self] output in
                guard let self, self.current == nil, let output else { return }
                let lines = output.components(separatedBy: "\n")
                guard lines.count >= 3 else { return }
                var duration = Self.number(lines[2])
                if player == .spotify, let d = duration { duration = d / 1000 }   // Spotify: milisekundy
                self.update(NowPlaying(player: player, title: lines[0], artist: lines[1], playing: true,
                                       duration: duration, position: nil, positionAt: nil,
                                       artwork: nil, tint: nil))
                self.loadArtwork(for: player, title: lines[0])
                self.refreshPosition()
            }
            return
        }
    }

    // MARK: - Okładka

    private func loadArtwork(for player: NowPlaying.Player, title: String) {
        guard isRunning(player) else { return }
        switch player {
        case .music:
            let source = """
            tell application "Music"
                try
                    return raw data of artwork 1 of current track
                end try
            end tell
            """
            runAsync(source) { [weak self] output in
                guard let output, let data = Self.dataFromAppleScript(output), let image = NSImage(data: data)
                else { return }
                self?.setArtwork(image, title: title)
            }
        case .spotify:
            runAsync("tell application \"Spotify\" to return artwork url of current track") { [weak self] output in
                guard let link = output?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let url = URL(string: link)
                else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async { self?.setArtwork(image, title: title) }
                }.resume()
            }
        }
    }

    private func setArtwork(_ image: NSImage, title: String) {
        guard var value = current, value.title == title else { return }
        value.artwork = image
        value.tint = image.vividAverageColor
        update(value)
    }

    /// osascript wypisuje dane binarne jako «data JPEG FFD8FF…» – zamieniamy szesnastkowe znaki na bajty.
    private static func dataFromAppleScript(_ text: String) -> Data? {
        guard let start = text.range(of: "«data "), let end = text.range(of: "»", range: start.upperBound..<text.endIndex)
        else { return nil }
        let body = text[start.upperBound..<end.lowerBound]
        guard body.count > 4 else { return nil }
        let hex = body.dropFirst(4)   // pomijamy 4-literowy typ, np. „JPEG” lub „tdta”
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Pozycja utworu (gdy panel jest rozwinięty – co 5 s korekta, między nimi liczymy sami)

    func trackPosition(_ on: Bool) {
        positionTimer?.invalidate()
        positionTimer = nil
        guard on else { return }
        refreshPosition()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshPosition()
        }
    }

    private func refreshPosition() {
        guard let player = current?.player, isRunning(player) else { return }
        runAsync("tell application \"\(player.appName)\" to return player position") { [weak self] output in
            guard let self, var value = self.current, value.player == player,
                  let output, let position = Self.number(output)
            else { return }
            value.position = position
            value.positionAt = Date()
            self.update(value)
        }
    }

    // MARK: - Sterowanie

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    /// Przewinięcie do wskazanej sekundy (przeciągnięcie paska postępu).
    func seek(to seconds: Double) {
        guard var value = current else { return }
        let target = max(0, seconds)
        command("set player position to \(String(format: "%.1f", target))")
        value.position = target
        value.positionAt = Date()
        update(value)
    }

    /// Otwiera program, który odtwarza muzykę (albo Muzykę, gdy nic nie gra).
    func openPlayer() {
        let id = current?.player.rawValue ?? NowPlaying.Player.music.rawValue
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        Log.write("Otwieram odtwarzacz: \(id)")
    }

    private func command(_ verb: String) {
        guard let player = current?.player, isRunning(player) else { return }
        runAsync("tell application \"\(player.appName)\" to \(verb)") { _ in }
        Log.write("Muzyka: \(verb) (\(player.displayName))")
    }

    // MARK: - Pomocnicze

    private func isRunning(_ player: NowPlaying.Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).isEmpty
    }

    /// Uruchamia AppleScript w osobnym procesie w tle (limit 4 s); wynik wraca na główny wątek.
    private func runAsync(_ source: String, completion: @escaping (String?) -> Void) {
        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Limit 4 s: zawieszony odtwarzacz nie może zablokować wcięcia.
            var timedOut = false
            let watchdog = DispatchWorkItem {
                if process.isRunning {
                    timedOut = true
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: watchdog)
            // Czytamy wyjście na bieżąco (okładka może mieć kilkaset KB – bufor potoku by się zapchał).
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errorData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            if timedOut {
                Log.write("Muzyka: odtwarzacz nie odpowiada – pominięto zapytanie")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            if errorText.contains("-1743") {
                Log.write("Muzyka: brak zgody na sterowanie odtwarzaczem (Ustawienia → Prywatność i ochrona → Automatyzacja)")
            }
            var text = String(data: data, encoding: .utf8)
            if let t = text, t.hasSuffix("\n") { text = String(t.dropLast()) }
            let result = (process.terminationStatus == 0 && !(text ?? "").isEmpty) ? text : nil
            DispatchQueue.main.async { completion(result) }
        }
    }
}

// MARK: - Kolor z okładki

extension NSImage {
    /// Średni kolor okładki, rozjaśniony i nasycony tak, żeby był dobrze widoczny na czarnym tle.
    var vividAverageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let average = NSColor(srgbRed: CGFloat(data[0]) / 255, green: CGFloat(data[1]) / 255,
                              blue: CGFloat(data[2]) / 255, alpha: 1)
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        average.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        if sat < 0.12 { return NSColor(white: 0.92, alpha: 1) }
        return NSColor(hue: h, saturation: max(sat, 0.55), brightness: max(b, 0.85), alpha: 1)
    }
}
