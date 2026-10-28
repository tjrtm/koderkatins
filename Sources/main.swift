// Koderkatins: a desktop pet that shows Claude Code token usage and plan limits.
// Not affiliated with or endorsed by Anthropic. MIT licence; see LICENSE.
import AppKit
import SwiftUI
import Combine
import ServiceManagement

// MARK: - Model

@MainActor final class PetModel: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var running = 0
    @Published var five: Limit?
    @Published var week: Limit?
    @Published var limitError: String?
    @Published var pets: [PetEntry] = []
    @Published var sprite: Sprite?
    @Published var hookInstalled = false
    @Published private(set) var celebrateUntil = Date.distantPast

    let prefs = Prefs.shared
    private let scanner = LogScanner(useCache: !CommandLine.arguments.contains("--cold"))
    private let queue = DispatchQueue(label: "koderkatins.scan", qos: .utility)
    private let alerts = AlertEngine()
    private var attention: [String: (msg: String, at: Date)] = [:]   // session id -> hook message
    private var scanning = false
    private var bag = Set<AnyCancellable>()
    private var lastTurnEnds: [String: Date] = [:]

    init() {
        if prefs.limitsNeeded { five = limitsCache.five; week = limitsCache.week }   // last known values, instantly
        reloadPets()
        prefs.$petID.dropFirst().sink { [weak self] id in self?.loadSprite(id) }.store(in: &bag)
        // switching limits on/off (or what uses them) takes effect right away
        Publishers.CombineLatest4(prefs.$limitsOnline, prefs.$showFiveHour, prefs.$showWeekly,
                                  Publishers.CombineLatest(prefs.$fiveHourAlert, prefs.$weeklyAlert))
            .dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor in await self?.refreshLimits() } }.store(in: &bag)
        prefs.$limitsEveryMin.dropFirst().sink { [weak self] _ in Task { @MainActor in self?.schedule() } }.store(in: &bag)
        refreshLogs()
        Task { await refreshLimits() }
        // Event-driven: rescan when Claude Code writes a log or the hook drops a signal (coalesced to 1 s).
        let home = FileManager.default.homeDirectoryForCurrentUser
        try? FileManager.default.createDirectory(at: Signals.dir, withIntermediateDirectories: true)
        watchers = [home.appendingPathComponent(".claude/projects").path, Signals.dir.path].map {
            FileWatcher(path: $0) { [weak self] in self?.refreshLogs() }
        }
        // Slow safety-net timer: expires old sessions and flips "working" to idle when logs go quiet.
        schedule()
        let ws = NSWorkspace.shared.notificationCenter
        for (n, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
                            (NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setAsleep(asleep) }
            }
        }
    }

    private var watchers: [FileWatcher] = []
    private var lastHookCheck = Date.distantPast
    private var timers: [Timer] = []
    /// True while the screen is off or the user switched away: no animation, slow polling.
    @Published private(set) var asleep = false

    private func setAsleep(_ a: Bool) {
        guard a != asleep else { return }
        asleep = a
        schedule()
        if !a { refreshLogs(); Task { await refreshLimits() } }
    }

    private func schedule() {
        timers.forEach { $0.invalidate() }
        let logEvery: TimeInterval = asleep ? 120 : 10
        // refreshLimits itself enforces the interval; the timer only gives it a chance to run
        let limitEvery: TimeInterval = asleep ? 900 : TimeInterval(max(1, prefs.limitsEveryMin) * 60)
        timers = [
            Timer.scheduledTimer(withTimeInterval: logEvery, repeats: true) { _ in Task { @MainActor in self.refreshLogs() } },
            Timer.scheduledTimer(withTimeInterval: limitEvery, repeats: true) { _ in Task { @MainActor in await self.refreshLimits() } },
        ]
        timers.forEach { $0.tolerance = $0.timeInterval * 0.2 }   // lets macOS batch wake-ups
    }

    // Pets
    func reloadPets(force: Bool = true) {
        let list = PetLibrary.all()
        if list != pets { pets = list }
        if force || sprite == nil || loadedSheet != currentEntry?.sheet { loadSprite(prefs.petID) }
    }
    private var loadedSheet: URL?
    private var currentEntry: PetEntry? { pets.first { $0.id == prefs.petID } ?? pets.first }
    func loadSprite(_ id: String) {
        let entry = pets.first { $0.id == id } ?? pets.first
        loadedSheet = entry?.sheet
        sprite = entry.flatMap { Sprite(url: $0.sheet) }
    }

    /// Flush the scan cache so the next launch starts instantly.
    func saveCache() { queue.sync { scanner.save(force: true) } }

    // Data
    func refreshLogs() {
        guard !scanning else { return }
        scanning = true
        let window = TimeInterval(prefs.activeMinutes * 60)
        queue.async { [scanner] in
            let s = scanner.scan(activeWindow: window)
            let n = LogScanner.runningProcesses()
            let sig = Signals.drain()
            DispatchQueue.main.async { self.apply(s, running: n, signals: sig) }
        }
        if Date().timeIntervalSince(lastHookCheck) > 30 {        // settings.json rarely changes
            lastHookCheck = Date()
            let hook = Self.checkHook()
            if hook != hookInstalled { hookInstalled = hook }
        }
    }

    private func apply(_ list: [SessionInfo], running n: Int, signals: [Signals.Signal]) {
        scanning = false
        var s = list
        for sig in signals where sig.event == nil || sig.event == "Notification" {
            let id = sig.session ?? s.first?.id ?? "?"
            attention[id] = (sig.message ?? "Claude needs your attention", Date())
            alerts.attention(prefs: prefs)
        }
        for i in s.indices {
            // cleared once the session writes new log activity after the notification
            if let a = attention[s[i].id], s[i].lastActivity > a.at.addingTimeInterval(3) { attention[s[i].id] = nil }
            if let a = attention[s[i].id] { s[i].needsAttention = true; s[i].attentionMessage = a.msg }
            if let at = s[i].turnEndedAt, s[i].turnEnded, lastTurnEnds[s[i].id] != at {
                if lastTurnEnds[s[i].id] != nil || Date().timeIntervalSince(at) < 10 { celebrateUntil = Date().addingTimeInterval(5) }
                lastTurnEnds[s[i].id] = at
            }
        }
        // publish only real changes: every publish re-renders the panel and re-fits the window
        if s != sessions { sessions = s }
        if n != running { running = n }
        alerts.evaluate(model: self, prefs: prefs)
    }

    private var limitsCache = LimitsCache.load()
    private var fetchingLimits = false

    /// Asks api.anthropic.com for the plan limits, at most once per interval (also across relaunches),
    /// and never while the server has asked us to back off. `force` (Refresh Now) skips only the interval.
    func refreshLimits(force: Bool = false) async {
        guard prefs.limitsNeeded else {
            if five != nil { five = nil }
            if week != nil { week = nil }
            if limitError != nil { limitError = nil }
            return
        }
        let now = Date()
        let interval = TimeInterval(max(1, prefs.limitsEveryMin) * 60)
        if now < limitsCache.retryAfter { showPaused(); return }
        guard !fetchingLimits, force || now.timeIntervalSince(limitsCache.attemptAt) >= interval - 5 else { return }
        fetchingLimits = true
        defer { fetchingLimits = false }
        limitsCache.attemptAt = now
        let (a, b, e) = await UsageAPI.fetch()
        if a != nil || b != nil {
            limitsCache.five = a; limitsCache.week = b
            limitsCache.fetchedAt = Date(); limitsCache.backoff = 0
            if a != five { five = a }
            if b != week { week = b }
            if limitError != nil { limitError = nil }
        } else if let e, e.hasPrefix("HTTP 429") {
            // too many requests: wait 5, 10, 20 … up to 60 min, keep showing the last values
            limitsCache.backoff = min(max(300, limitsCache.backoff * 2), 3600)
            limitsCache.retryAfter = Date().addingTimeInterval(limitsCache.backoff)
            showPaused()
        } else if e != limitError {
            limitError = e
        }
        limitsCache.save()
        alerts.evaluate(model: self, prefs: prefs)
    }

    private func showPaused() {
        let f = DateFormatter(); f.timeStyle = .short
        let msg = "paused by Anthropic, retrying at \(f.string(from: limitsCache.retryAfter))"
        if limitError != msg { limitError = msg }
    }

    var mood: PetMood {
        if sessions.contains(where: { $0.needsAttention }) { return .attention }
        if (five?.pct ?? 0) >= prefs.fiveHourThreshold || (week?.pct ?? 0) >= prefs.weeklyThreshold { return .worried }
        let working = sessions.filter { $0.working }
        if !working.isEmpty {
            // log just written → typing; quiet for a few seconds while still mid-turn → thinking
            return working.contains { Date().timeIntervalSince($0.lastActivity) < 6 } ? .working : .thinking
        }
        if Date() < celebrateUntil { return .done }
        return sessions.isEmpty ? .sleepy : .idle
    }

    func petClicked() {
        if !attention.isEmpty { attention.removeAll(); refreshLogs(); return }   // first click acknowledges
        prefs.showPanel.toggle()
    }

    // Optional Claude Code Notification hook (user adds it; we only read settings.json)
    nonisolated static let hookCommand = #"mkdir -p "$HOME/Library/Application Support/Koderkatins/signals" && cat > "$HOME/Library/Application Support/Koderkatins/signals/$(date +%s)-$$.json""#
    nonisolated static func checkHook() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return s.contains("Koderkatins/signals")
    }
    func copyHookSnippet() {
        let cmd = Self.hookCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let snippet = """
        "hooks": {
          "Notification": [
            { "hooks": [ { "type": "command", "command": "\(cmd)" } ] }
          ]
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
    }
}

// MARK: - Window / app

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: PetPanel!
    var status: NSStatusItem!
    var model: PetModel!
    var host: NSHostingView<PetView>!
    var settingsWindow: NSWindow?
    var bag = Set<AnyCancellable>()
    let prefs = Prefs.shared

    func applicationDidFinishLaunching(_ n: Notification) {
        model = PetModel()
        host = NSHostingView(rootView: PetView(model: model, prefs: prefs))
        host.sizingOptions = [.intrinsicContentSize]
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 400),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        fit()
        let key = "NSWindow Frame KoderkatinsPet"
        let restored = UserDefaults.standard.string(forKey: key) != nil && panel.setFrameUsingName("KoderkatinsPet")
        if !restored { placeBottomRight() }
        panel.orderFrontRegardless()
        // SwiftUI settles the final size a moment after launch: place again, then start remembering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            fit()
            if !restored { placeBottomRight() }
            panel.setFrameAutosaveName("KoderkatinsPet")
        }

        // keep the window hugging its content, anchored bottom-right (where the pet sits)
        prefs.objectWillChange.merge(with: model.objectWillChange)
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.fit() }.store(in: &bag)

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "🐾"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    func applicationWillTerminate(_ n: Notification) { model.saveCache() }

    func placeBottomRight() {
        let scr = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let v = scr?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: v.maxX - panel.frame.width - 16, y: v.minY + 16))
    }

    func fit() {
        let size = host.intrinsicContentSize
        guard size.width > 0, size.height > 0, size != panel.frame.size else { return }
        let f = panel.frame
        panel.setFrame(NSRect(x: f.maxX - size.width, y: f.minY, width: size.width, height: size.height), display: true)
    }

    @objc func toggle() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    @objc func togglePanel() { prefs.showPanel.toggle() }
    @objc func refresh() { model.refreshLogs(); Task { await model.refreshLimits(force: true) } }
    @objc func pickPet(_ i: NSMenuItem) { if let id = i.representedObject as? String { prefs.petID = id } }
    @objc func pickSize(_ i: NSMenuItem) { prefs.petScale = Double(i.tag) / 100 }
    @objc func pickMotion(_ i: NSMenuItem) { prefs.applyMotion(i.tag) }
    @objc func openPets() { NSWorkspace.shared.open(PetLibrary.userDir) }
    @objc func toggleSounds() { prefs.soundsOn.toggle() }
    @objc func toggleLimits() { prefs.limitsOnline.toggle() }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }
    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Koderkatins Settings"
            w.contentView = NSHostingView(rootView: SettingsView(prefs: prefs, model: model))
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt every time it opens, so checkmarks and the pet list are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ sel: Selector, _ key: String = "", on: Bool = false) {
            let i = menu.addItem(withTitle: title, action: sel, keyEquivalent: key)
            i.target = self; i.state = on ? .on : .off
        }
        add("Show Pet", #selector(toggle), "p", on: panel.isVisible)
        add("Show Stats Panel", #selector(togglePanel), "s", on: prefs.showPanel)
        add("Refresh Now", #selector(refresh), "r")
        menu.addItem(.separator())

        let pets = NSMenu()
        model.reloadPets(force: false)      // pick up new skin folders without re-decoding the current one
        for p in model.pets {
            let i = pets.addItem(withTitle: p.name, action: #selector(pickPet(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = p.id; i.state = p.id == prefs.petID ? .on : .off
        }
        pets.addItem(.separator())
        pets.addItem(withTitle: "Open Skins Folder…", action: #selector(openPets), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Skins", action: nil, keyEquivalent: "").submenu = pets

        let sizes = NSMenu()
        for (name, pct) in [("Small", 35), ("Medium", 50), ("Large", 75), ("Huge", 110)] {
            let i = sizes.addItem(withTitle: name, action: #selector(pickSize(_:)), keyEquivalent: "")
            i.target = self; i.tag = pct; i.state = abs(prefs.petScale * 100 - Double(pct)) < 1 ? .on : .off
        }
        menu.addItem(withTitle: "Size", action: nil, keyEquivalent: "").submenu = sizes

        let motion = NSMenu()
        for (i, name) in Prefs.motionNames.enumerated() {
            let it = motion.addItem(withTitle: name, action: #selector(pickMotion(_:)), keyEquivalent: "")
            it.target = self; it.tag = i; it.state = prefs.motion == i ? .on : .off
        }
        menu.addItem(withTitle: "Motion", action: nil, keyEquivalent: "").submenu = motion

        add("Sounds", #selector(toggleSounds), on: prefs.soundsOn)
        add("Check Plan Limits Online", #selector(toggleLimits), on: prefs.limitsOnline)
        menu.addItem(.separator())
        add("Settings…", #selector(openSettings), ",")
        add("Launch at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Koderkatins", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}

// MARK: - Entry point

if CommandLine.arguments.contains("--dump") {
    let t0 = Date()
    for s in LogScanner(useCache: !CommandLine.arguments.contains("--cold")).scan(activeWindow: 15 * 60) {
        print("\(s.title ?? "-") [\(s.project)] \(s.id.prefix(8)) in \(s.inputTokens) out \(s.outputTokens) cache \(s.cacheRead) ctx \(s.context)",
              s.working ? "WORKING" : s.turnEnded ? "YOUR-TURN" : "idle")
    }
    print("running processes:", LogScanner.runningProcesses(), String(format: "· scan %.2fs", Date().timeIntervalSince(t0)))
    print("skins:", PetLibrary.all().map(\.name).joined(separator: ", "))
    print("hook installed:", PetModel.checkHook())
    if CommandLine.arguments.contains("--limits") {          // live request: only when asked for
        let sem = DispatchSemaphore(value: 0)
        Task {
            let (a, b, e) = await UsageAPI.fetch()
            print("5-hour:", a.map { "\(Int($0.pct))% resets in \(until($0.resets))" } ?? "—",
                  "· weekly:", b.map { "\(Int($0.pct))% resets in \(until($0.resets))" } ?? "—", e ?? "")
            sem.signal()
        }
        sem.wait()
    } else {
        let c = LimitsCache.load()
        let ago = c.fetchedAt == .distantPast ? "never fetched" : "fetched \(Int(Date().timeIntervalSince(c.fetchedAt) / 60)) min ago"
        print("limits (cached, \(ago)):",
              c.five.map { "5-hour \(Int($0.pct))%" } ?? "—", "·", c.week.map { "weekly \(Int($0.pct))%" } ?? "—",
              "· add --limits to fetch live")
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
