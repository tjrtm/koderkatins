import Foundation
import SwiftUI

/// Every user setting lives here and is persisted in UserDefaults.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    private func bind<T>(_ key: String, _ def: T) -> T { (d.object(forKey: key) as? T) ?? def }

    // Pet
    @Published var petID: String { didSet { d.set(petID, forKey: "petID") } }
    @Published var petScale: Double { didSet { d.set(petScale, forKey: "petScale") } }
    @Published var frameDuration: Double { didSet { d.set(frameDuration, forKey: "frameDuration") } }   // seconds per frame
    @Published var smoothFrames: Bool { didSet { d.set(smoothFrames, forKey: "smoothFrames") } }        // cross-fade
    @Published var restSeconds: Double { didSet { d.set(restSeconds, forKey: "restSeconds") } }        // pause after each loop
    @Published var motion: Int { didSet { d.set(motion, forKey: "motion") } }                          // 0 still 1 calm 2 normal 3 lively 4 custom

    // Panel
    @Published var panelSize: Int { didSet { d.set(panelSize, forKey: "panelSize") } }      // 0 compact 1 regular 2 large
    @Published var showPanel: Bool { didSet { d.set(showPanel, forKey: "showPanel") } }
    @Published var showCounts: Bool { didSet { d.set(showCounts, forKey: "showCounts") } }
    @Published var showFiveHour: Bool { didSet { d.set(showFiveHour, forKey: "showFiveHour") } }
    @Published var showWeekly: Bool { didSet { d.set(showWeekly, forKey: "showWeekly") } }
    @Published var showSessions: Bool { didSet { d.set(showSessions, forKey: "showSessions") } }
    @Published var showTitles: Bool { didSet { d.set(showTitles, forKey: "showTitles") } }
    @Published var showInOut: Bool { didSet { d.set(showInOut, forKey: "showInOut") } }
    @Published var showCache: Bool { didSet { d.set(showCache, forKey: "showCache") } }
    @Published var showContext: Bool { didSet { d.set(showContext, forKey: "showContext") } }
    @Published var showTotals: Bool { didSet { d.set(showTotals, forKey: "showTotals") } }
    @Published var maxSessions: Int { didSet { d.set(maxSessions, forKey: "maxSessions") } }   // 0 = all
    @Published var activeMinutes: Int { didSet { d.set(activeMinutes, forKey: "activeMinutes") } }

    // Plan limits (the only network access the app makes)
    @Published var limitsOnline: Bool { didSet { d.set(limitsOnline, forKey: "limitsOnline") } }
    @Published var limitsEveryMin: Int { didSet { d.set(limitsEveryMin, forKey: "limitsEveryMin") } }

    // Alerts
    @Published var soundsOn: Bool { didSet { d.set(soundsOn, forKey: "soundsOn") } }
    @Published var volume: Double { didSet { d.set(volume, forKey: "volume") } }
    @Published var fiveHourAlert: Bool { didSet { d.set(fiveHourAlert, forKey: "fiveHourAlert") } }
    @Published var fiveHourThreshold: Double { didSet { d.set(fiveHourThreshold, forKey: "fiveHourThreshold") } }
    @Published var fiveHourRepeatMin: Double { didSet { d.set(fiveHourRepeatMin, forKey: "fiveHourRepeatMin") } }
    @Published var fiveHourSound: String { didSet { d.set(fiveHourSound, forKey: "fiveHourSound") } }
    @Published var weeklyAlert: Bool { didSet { d.set(weeklyAlert, forKey: "weeklyAlert") } }
    @Published var weeklyThreshold: Double { didSet { d.set(weeklyThreshold, forKey: "weeklyThreshold") } }
    @Published var weeklyRepeatMin: Double { didSet { d.set(weeklyRepeatMin, forKey: "weeklyRepeatMin") } }
    @Published var weeklySound: String { didSet { d.set(weeklySound, forKey: "weeklySound") } }
    @Published var sessionsAlert: Bool { didSet { d.set(sessionsAlert, forKey: "sessionsAlert") } }
    @Published var sessionsThreshold: Int { didSet { d.set(sessionsThreshold, forKey: "sessionsThreshold") } }
    @Published var sessionsSound: String { didSet { d.set(sessionsSound, forKey: "sessionsSound") } }
    @Published var turnDoneAlert: Bool { didSet { d.set(turnDoneAlert, forKey: "turnDoneAlert") } }
    @Published var turnDoneSound: String { didSet { d.set(turnDoneSound, forKey: "turnDoneSound") } }
    @Published var attentionAlert: Bool { didSet { d.set(attentionAlert, forKey: "attentionAlert") } }
    @Published var attentionSound: String { didSet { d.set(attentionSound, forKey: "attentionSound") } }

    private init() {
        let d = UserDefaults.standard
        func v<T>(_ k: String, _ def: T) -> T { (d.object(forKey: k) as? T) ?? def }
        petID = v("petID", "claudiks"); petScale = v("petScale", 0.5)
        frameDuration = v("frameDuration", 0.3); smoothFrames = v("smoothFrames", true)
        restSeconds = v("restSeconds", 2.0); motion = v("motion", 1)
        panelSize = v("panelSize", 1); showPanel = v("showPanel", true)
        showCounts = v("showCounts", true); showFiveHour = v("showFiveHour", true); showWeekly = v("showWeekly", true)
        showSessions = v("showSessions", true); showTitles = v("showTitles", true); showInOut = v("showInOut", true)
        showCache = v("showCache", false); showContext = v("showContext", true); showTotals = v("showTotals", true)
        maxSessions = v("maxSessions", 0); activeMinutes = v("activeMinutes", 15)
        limitsOnline = v("limitsOnline", true); limitsEveryMin = v("limitsEveryMin", 2)
        soundsOn = v("soundsOn", true); volume = v("volume", 0.7)
        fiveHourAlert = v("fiveHourAlert", true); fiveHourThreshold = v("fiveHourThreshold", 90)
        fiveHourRepeatMin = v("fiveHourRepeatMin", 3); fiveHourSound = v("fiveHourSound", "system:Purr")
        weeklyAlert = v("weeklyAlert", false); weeklyThreshold = v("weeklyThreshold", 90)
        weeklyRepeatMin = v("weeklyRepeatMin", 30); weeklySound = v("weeklySound", "system:Purr")
        sessionsAlert = v("sessionsAlert", true); sessionsThreshold = v("sessionsThreshold", 5)
        sessionsSound = v("sessionsSound", "system:Pop")
        turnDoneAlert = v("turnDoneAlert", false); turnDoneSound = v("turnDoneSound", "system:Glass")
        attentionAlert = v("attentionAlert", true); attentionSound = v("attentionSound", "system:Purr")
    }

    static let motionNames = ["Still", "Calm", "Normal", "Lively"]
    /// Apply a motion preset (speed + rest). Moving the sliders afterwards switches to "Custom".
    func applyMotion(_ m: Int) {
        let presets: [(Double, Double)] = [(0.4, 0), (0.3, 2.0), (0.2, 0.6), (0.13, 0)]
        guard presets.indices.contains(m) else { return }
        frameDuration = presets[m].0; restSeconds = presets[m].1; motion = m
    }

    /// Limits are fetched only when switched on AND something actually uses them.
    var limitsNeeded: Bool { limitsOnline && (showFiveHour || showWeekly || fiveHourAlert || weeklyAlert) }

    /// Panel width and text scale for the three size presets.
    var panelWidth: CGFloat { [220, 270, 340][max(0, min(2, panelSize))] }
    var textScale: CGFloat { [0.9, 1.0, 1.2][max(0, min(2, panelSize))] }
}
