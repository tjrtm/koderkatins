import AppKit

/// Sound references are strings: "system:Purr" for a built-in macOS sound, "none",
/// or an absolute path to an audio file (mp3, wav, aiff, m4a…).
enum Sounds {
    static let systemNames = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                              "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    static var userDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Koderkatins/Sounds", isDirectory: true)
    }
    /// Audio files dropped into the Sounds folder appear in every sound picker.
    static func userFiles() -> [URL] {
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        let exts: Set<String> = ["mp3", "wav", "aiff", "aif", "m4a", "caf"]
        return ((try? FileManager.default.contentsOfDirectory(at: userDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { exts.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func label(_ ref: String) -> String {
        if ref == "none" { return "None" }
        if ref.hasPrefix("system:") { return String(ref.dropFirst(7)) }
        return URL(fileURLWithPath: ref).deletingPathExtension().lastPathComponent
    }

    private static var playing: [NSSound] = []

    static func play(_ ref: String, volume: Double) {
        Debug.event("sound", "\(ref) volume \(String(format: "%.2f", volume))")
        guard ref != "none" else { return }
        let s: NSSound? = ref.hasPrefix("system:") ? NSSound(named: NSSound.Name(String(ref.dropFirst(7))))?.copy() as? NSSound
                                                   : NSSound(contentsOfFile: ref, byReference: true)
        guard let s else { NSSound.beep(); return }
        s.volume = Float(volume)
        playing.append(s)
        playing = playing.filter { $0.isPlaying || $0 === s }
        s.play()
    }
}

/// Decides when to play which alert. Called after each data refresh.
@MainActor final class AlertEngine {
    private var lastPlayed: [String: Date] = [:]
    private var sessionsWasOver = false
    private var seenTurnEnds: [String: Date] = [:]
    private var primed = false

    func evaluate(model: PetModel, prefs: Prefs) {
        defer { primed = true }
        guard prefs.soundsOn else { return }
        let now = Date()

        func repeating(_ key: String, active: Bool, every minutes: Double, sound: String) {
            guard active else { lastPlayed[key] = nil; return }
            if let last = lastPlayed[key], now.timeIntervalSince(last) < max(0.25, minutes) * 60 { return }
            lastPlayed[key] = now
            Sounds.play(sound, volume: prefs.volume)
        }

        repeating("5h", active: prefs.fiveHourAlert && (model.five?.pct ?? 0) >= prefs.fiveHourThreshold,
                  every: prefs.fiveHourRepeatMin, sound: prefs.fiveHourSound)
        repeating("week", active: prefs.weeklyAlert && (model.week?.pct ?? 0) >= prefs.weeklyThreshold,
                  every: prefs.weeklyRepeatMin, sound: prefs.weeklySound)

        let over = model.sessions.count > prefs.sessionsThreshold
        if prefs.sessionsAlert, over, !sessionsWasOver, primed { Sounds.play(prefs.sessionsSound, volume: prefs.volume) }
        sessionsWasOver = over

        for s in model.sessions {
            guard let at = s.turnEndedAt, s.turnEnded else { continue }
            if seenTurnEnds[s.id] != at {
                let fresh = now.timeIntervalSince(at) < 60
                if primed, fresh, prefs.turnDoneAlert { Sounds.play(prefs.turnDoneSound, volume: prefs.volume) }
                seenTurnEnds[s.id] = at
            }
        }
    }

    func attention(prefs: Prefs) {
        guard prefs.soundsOn, prefs.attentionAlert else { return }
        Sounds.play(prefs.attentionSound, volume: prefs.volume)
    }
}
