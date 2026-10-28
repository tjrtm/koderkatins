import Foundation

/// Opt-in diagnostics for testing: launch with KODERKATINS_DEBUG=1 and the app keeps
/// ~/Library/Caches/Koderkatins/debug-state.json up to date with what it is actually doing
/// (player speed, window size, sounds played, limit requests…). Off by default; costs nothing when off.
enum Debug {
    static let on = ProcessInfo.processInfo.environment["KODERKATINS_DEBUG"] == "1"
    private static var state: [String: Any] = [:]
    private static var pending = false

    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Koderkatins/debug-state.json")
    }

    static func set(_ key: String, _ value: Any) {
        guard on else { return }
        state[key] = value
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pending = false
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
                try? d.write(to: url, options: .atomic)
            }
        }
    }

    static func event(_ name: String, _ detail: String) {
        guard on else { return }
        var log = state["events"] as? [String] ?? []
        log.append("\(Int(Date().timeIntervalSince1970)) \(name): \(detail)")
        set("events", Array(log.suffix(40)))
    }
}
