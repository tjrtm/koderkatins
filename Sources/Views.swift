import SwiftUI
import AppKit
import UniformTypeIdentifiers

func fmt(_ n: Int) -> String {
    switch n {
    case 1_000_000_000...: return String(format: "%.2fB", Double(n) / 1e9)
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1e6)
    case 1_000...: return String(format: "%.0fk", Double(n) / 1e3)
    default: return "\(n)"
    }
}

func until(_ d: Date?) -> String {
    guard let d else { return "" }
    let s = max(0, Int(d.timeIntervalSinceNow)), h = s / 3600, m = (s % 3600) / 60
    return h >= 24 ? "\(h / 24)d \(h % 24)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

// MARK: - Pet + panel

struct LimitBar: View {
    let label: String; let limit: Limit?; let scale: CGFloat
    var body: some View {
        let p = (limit?.pct ?? 0) / 100
        let color: Color = p >= 0.9 ? .red : p >= 0.7 ? .orange : .green
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 10 * scale, weight: .semibold))
                Spacer()
                Text(limit.map { "\(Int($0.pct.rounded()))%" } ?? "—")
                    .font(.system(size: 10 * scale, weight: .bold).monospacedDigit())
                if let r = limit?.resets {
                    Text("↺ \(until(r))").font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(color).frame(width: max(4, g.size.width * min(p, 1)))
                }
            }.frame(height: 5 * scale)
        }
    }
}

struct SessionRow: View {
    let s: SessionInfo; @ObservedObject var prefs: Prefs
    var body: some View {
        let sc = prefs.textScale
        let (dot, state): (Color, String) =
            s.needsAttention ? (.red, "needs you") :
            s.working ? (.green, "working") :
            s.turnEnded ? (.yellow, "your turn") : (.gray, "idle")
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(dot).frame(width: 6 * sc, height: 6 * sc)
                Text(prefs.showTitles ? (s.title ?? s.project) : s.project)
                    .font(.system(size: 10.5 * sc, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(state).font(.system(size: 9 * sc)).foregroundStyle(dot == .gray ? Color.secondary : dot)
            }
            if prefs.showTitles, s.title != nil {
                Text(s.project).font(.system(size: 9 * sc)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            if let m = s.attentionMessage, s.needsAttention {
                Text(m).font(.system(size: 9 * sc)).foregroundStyle(.red).lineLimit(2)
            }
            let parts = [prefs.showInOut ? "in \(fmt(s.inputTokens)) · out \(fmt(s.outputTokens))" : nil,
                         prefs.showCache ? "cache \(fmt(s.cacheRead))" : nil,
                         prefs.showContext ? "ctx \(fmt(s.context))" : nil].compactMap { $0 }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(.system(size: 9.5 * sc).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

struct StatsPanel: View {
    @ObservedObject var model: PetModel
    @ObservedObject var prefs: Prefs
    var body: some View {
        let sc = prefs.textScale
        let shown = prefs.maxSessions > 0 ? Array(model.sessions.prefix(prefs.maxSessions)) : model.sessions
        VStack(alignment: .leading, spacing: 7 * sc) {
            HStack {
                Text("Claude Code").font(.system(size: 11.5 * sc, weight: .bold))
                Spacer()
                if prefs.showCounts {
                    Label("\(model.running) running · \(model.sessions.count) active", systemImage: "terminal")
                        .font(.system(size: 9.5 * sc)).foregroundStyle(.secondary)
                }
            }
            if prefs.limitsOnline, prefs.showFiveHour { LimitBar(label: "5-hour", limit: model.five, scale: sc) }
            if prefs.limitsOnline, prefs.showWeekly { LimitBar(label: "Weekly", limit: model.week, scale: sc) }
            if let e = model.limitError, prefs.limitsOnline, prefs.showFiveHour || prefs.showWeekly {
                Text("limits \(e)").font(.system(size: 9 * sc)).foregroundStyle(.orange)
            }
            if prefs.showSessions {
                Divider().opacity(0.4)
                if model.sessions.isEmpty {
                    Text("No sessions active in the last \(prefs.activeMinutes) min")
                        .font(.system(size: 9.5 * sc)).foregroundStyle(.secondary)
                } else {
                    ScrollView(.vertical, showsIndicators: shown.count > 5) {
                        VStack(alignment: .leading, spacing: 7 * sc) {
                            ForEach(shown) { SessionRow(s: $0, prefs: prefs) }
                        }
                    }
                    .frame(maxHeight: CGFloat(min(shown.count, 6)) * 52 * sc)
                    if shown.count < model.sessions.count {
                        Text("+ \(model.sessions.count - shown.count) more").font(.system(size: 9 * sc)).foregroundStyle(.secondary)
                    }
                }
            }
            if prefs.showTotals, model.sessions.count > 1 {
                let tin = model.sessions.reduce(0) { $0 + $1.inputTokens }
                let tout = model.sessions.reduce(0) { $0 + $1.outputTokens }
                Text("All sessions: in \(fmt(tin)) · out \(fmt(tout))")
                    .font(.system(size: 9.5 * sc, weight: .semibold).monospacedDigit())
            }
        }
        .padding(10 * sc)
        .frame(width: prefs.panelWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }
}

/// Container: panel + pet. Holds no animation state, so frame ticks never re-render the panel.
struct PetView: View {
    @ObservedObject var model: PetModel
    @ObservedObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if prefs.showPanel {
                StatsPanel(model: model, prefs: prefs)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
            }
            SpriteView(model: model, prefs: prefs)
        }
        .padding(6)
        .fixedSize()
        .animation(.easeOut(duration: 0.18), value: prefs.showPanel)
    }
}

/// The animated pet. Frame playback lives in `SpritePlayerView` (Core Animation), so SwiftUI only
/// re-renders this when a setting or the skin changes, never once per frame.
struct SpriteView: View {
    @ObservedObject var model: PetModel
    @ObservedObject var prefs: Prefs

    var body: some View {
        let size = model.sprite?.frameSize ?? NSSize(width: 192, height: 208)
        let w = (size.width * prefs.petScale).rounded(), h = (size.height * prefs.petScale).rounded()
        Group {
            if model.sprite == nil {
                Text("🐱").font(.system(size: 100 * prefs.petScale))
            } else {
                SpritePlayer(model: model, prefs: prefs).frame(width: w, height: h)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.petClicked() }
        .help("Click: show/hide stats · Drag: move · 🐾 menu-bar icon for settings")
    }
}

private struct SpritePlayer: NSViewRepresentable {
    let model: PetModel
    let prefs: Prefs

    func makeNSView(context: Context) -> SpritePlayerView {
        let v = SpritePlayerView(frame: .zero)
        v.mood = { [weak model] in model?.mood ?? .idle }
        return v
    }

    func updateNSView(_ v: SpritePlayerView, context: Context) {
        v.restSeconds = prefs.restSeconds
        v.motion = prefs.motion
        v.smooth = prefs.smoothFrames
        v.frameDuration = prefs.frameDuration
        v.scale = prefs.petScale
        v.paused = model.asleep
        v.sprite = model.sprite
    }
}

// MARK: - Settings

struct SoundPicker: View {
    let title: String
    @Binding var ref: String
    var body: some View {
        HStack {
            Picker(title, selection: $ref) {
                Text("None").tag("none")
                Section("macOS") { ForEach(Sounds.systemNames, id: \.self) { Text($0).tag("system:\($0)") } }
                let files = Sounds.userFiles()
                if !files.isEmpty { Section("Sounds folder") { ForEach(files, id: \.path) { Text($0.deletingPathExtension().lastPathComponent).tag($0.path) } } }
                if ref != "none", !ref.hasPrefix("system:"), !Sounds.userFiles().contains(where: { $0.path == ref }) {
                    Text(Sounds.label(ref)).tag(ref)
                }
            }
            Button("File…") {
                let p = NSOpenPanel(); p.allowedContentTypes = [.audio]
                if p.runModal() == .OK, let u = p.url { ref = u.path }
            }
            Button { Sounds.play(ref, volume: Prefs.shared.volume) } label: { Image(systemName: "play.fill") }
                .help("Preview")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var model: PetModel

    var body: some View {
        TabView {
            Form {
                Section("Skin") {
                    Picker("Skin", selection: $prefs.petID) {
                        ForEach(model.pets) { Text($0.name + ($0.builtIn ? "" : "  (yours)")).tag($0.id) }
                    }
                }
                Section {
                    Picker("Preset", selection: Binding(get: { prefs.motion }, set: { prefs.applyMotion($0) })) {
                        ForEach(0..<4) { Text(Prefs.motionNames[$0]).tag($0) }
                        if prefs.motion == 4 { Text("Custom").tag(4) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Slider(value: Binding(get: { 1 / prefs.frameDuration }, set: { prefs.frameDuration = 1 / $0; prefs.motion = 4 }),
                               in: 2...8) { Text("Speed") }
                        Text(String(format: "%.1f fps", 1 / prefs.frameDuration)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                    HStack {
                        Slider(value: Binding(get: { prefs.restSeconds }, set: { prefs.restSeconds = $0; prefs.motion = 4 }),
                               in: 0...10, step: 0.5) { Text("Rest between loops") }
                        Text(String(format: "%.1f s", prefs.restSeconds)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                    Toggle("Smooth frames (cross-fade)", isOn: $prefs.smoothFrames)
                } header: { Text("Motion") } footer: {
                    Text("Still holds one pose and only animates when a session needs you or finishes. Idle and sleepy always play at half speed.")
                }
                Section("Size") {
                    HStack {
                        Slider(value: $prefs.petScale, in: 0.25...1.5) { Text("Size") }
                        Text("\(Int(prefs.petScale * 192)) px").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                    HStack {
                        Button("Open Skins Folder") { NSWorkspace.shared.open(PetLibrary.userDir) }
                        Button("Reload Skins") { model.reloadPets() }
                        Spacer()
                        Link("How to make a skin", destination: URL(string: "https://github.com/tjrtm/koderkatins/blob/main/docs/SPRITES.md")!)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Koderkatins", systemImage: "pawprint") }

            Form {
                Section("Panel") {
                    Toggle("Show stats panel", isOn: $prefs.showPanel)
                    Picker("Size", selection: $prefs.panelSize) {
                        Text("Compact").tag(0); Text("Regular").tag(1); Text("Large").tag(2)
                    }.pickerStyle(.segmented)
                }
                Section {
                    Toggle("Check plan limits online", isOn: $prefs.limitsOnline)
                    Picker("Check every", selection: $prefs.limitsEveryMin) {
                        Text("1 min").tag(1); Text("2 min").tag(2); Text("5 min").tag(5); Text("10 min").tag(10); Text("30 min").tag(30)
                    }.disabled(!prefs.limitsOnline)
                } header: { Text("Plan limits") } footer: {
                    Text("The 5-hour and weekly percentages only exist on Anthropic's side, so Koderkatins asks api.anthropic.com for them using Claude Code's saved login. It sends nothing else, uses no tokens and doesn't count against your limits. Everything else is read from local log files. Turn this off and the app never goes online.")
                }
                Section("Show") {
                    Toggle("Running / active session counts", isOn: $prefs.showCounts)
                    Toggle("5-hour limit", isOn: $prefs.showFiveHour).disabled(!prefs.limitsOnline)
                    Toggle("Weekly limit", isOn: $prefs.showWeekly).disabled(!prefs.limitsOnline)
                    Toggle("Session list", isOn: $prefs.showSessions)
                    Toggle("Session titles (instead of folder names)", isOn: $prefs.showTitles).disabled(!prefs.showSessions)
                    Toggle("Input / output tokens", isOn: $prefs.showInOut).disabled(!prefs.showSessions)
                    Toggle("Cache-read tokens", isOn: $prefs.showCache).disabled(!prefs.showSessions)
                    Toggle("Context size", isOn: $prefs.showContext).disabled(!prefs.showSessions)
                    Toggle("Totals across sessions", isOn: $prefs.showTotals)
                }
                Section("Sessions") {
                    Stepper(prefs.maxSessions == 0 ? "Show all active sessions" : "Show at most \(prefs.maxSessions)",
                            value: $prefs.maxSessions, in: 0...20)
                    Stepper("Active = used in the last \(prefs.activeMinutes) min", value: $prefs.activeMinutes, in: 1...240)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Display", systemImage: "rectangle.3.group") }

            Form {
                Section {
                    Toggle("Play sounds", isOn: $prefs.soundsOn)
                    HStack { Text("Volume"); Slider(value: $prefs.volume, in: 0...1) }
                    Button("Open Sounds Folder") { NSWorkspace.shared.open(Sounds.userDir) }
                        .help("Audio files you put here appear in every sound picker")
                }
                Section("5-hour limit") {
                    Toggle("Alert when usage is high", isOn: $prefs.fiveHourAlert)
                    Stepper("At \(Int(prefs.fiveHourThreshold))% or more", value: $prefs.fiveHourThreshold, in: 10...100, step: 5)
                    Stepper("Repeat every \(fmtMin(prefs.fiveHourRepeatMin))", value: $prefs.fiveHourRepeatMin, in: 0.5...60, step: 0.5)
                    SoundPicker(title: "Sound", ref: $prefs.fiveHourSound)
                }.disabled(!prefs.soundsOn)
                Section("Weekly limit") {
                    Toggle("Alert when usage is high", isOn: $prefs.weeklyAlert)
                    Stepper("At \(Int(prefs.weeklyThreshold))% or more", value: $prefs.weeklyThreshold, in: 10...100, step: 5)
                    Stepper("Repeat every \(fmtMin(prefs.weeklyRepeatMin))", value: $prefs.weeklyRepeatMin, in: 1...240, step: 1)
                    SoundPicker(title: "Sound", ref: $prefs.weeklySound)
                }.disabled(!prefs.soundsOn)
                Section("Many sessions") {
                    Toggle("Alert when active sessions go above", isOn: $prefs.sessionsAlert)
                    Stepper("\(prefs.sessionsThreshold) sessions", value: $prefs.sessionsThreshold, in: 1...50)
                    SoundPicker(title: "Sound", ref: $prefs.sessionsSound)
                }.disabled(!prefs.soundsOn)
                Section {
                    Toggle("A session finished its turn (your move)", isOn: $prefs.turnDoneAlert)
                    SoundPicker(title: "Sound", ref: $prefs.turnDoneSound)
                    Toggle("A session needs attention (permission / input)", isOn: $prefs.attentionAlert)
                    SoundPicker(title: "Sound", ref: $prefs.attentionSound)
                    HStack {
                        Text(model.hookInstalled ? "✓ Claude Code notification hook is installed" : "Needs a one-line Claude Code hook")
                            .foregroundStyle(model.hookInstalled ? .green : .secondary)
                        Spacer()
                        Button("Copy Hook Setup") { model.copyHookSnippet() }
                    }.font(.callout)
                } header: { Text("Session events") } footer: {
                    Text("\"Finished its turn\" is read from the session logs. \"Needs attention\" comes from Claude Code's own Notification hook, which you add to ~/.claude/settings.json yourself (see README); Koderkatins never edits Claude Code's settings.")
                }.disabled(!prefs.soundsOn)
            }
            .formStyle(.grouped)
            .tabItem { Label("Alerts", systemImage: "bell") }
        }
        .frame(width: 520, height: 600)
    }

    func fmtMin(_ m: Double) -> String { m < 1 ? "\(Int(m * 60)) s" : m == m.rounded() ? "\(Int(m)) min" : String(format: "%.1f min", m) }
}
