import Foundation

struct Limit: Equatable, Codable { var pct: Double; var resets: Date? }

/// Last fetched limits and the retry schedule, kept across launches so restarting the app
/// never causes an extra request.
struct LimitsCache: Codable {
    var five: Limit?
    var week: Limit?
    var fetchedAt = Date.distantPast       // last successful reply
    var attemptAt = Date.distantPast       // last request of any kind
    var retryAfter = Date.distantPast      // set when the server says "too many requests"
    var backoff: TimeInterval = 0

    private static let key = "limitsCache"
    static func load() -> LimitsCache {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(LimitsCache.self, from: $0) } ?? LimitsCache()
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) } }
}

/// Plan limits. This is the same (undocumented) endpoint Claude Code's /usage uses;
/// it may change at any time. The OAuth token is read fresh from the login Keychain
/// for each request and never stored, logged or sent anywhere but api.anthropic.com.
enum UsageAPI {
    static func token() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let oa = o["claudeAiOauth"] as? [String: Any] else { return nil }
        return oa["accessToken"] as? String
    }

    static func fetch() async -> (Limit?, Limit?, String?) {
        guard let t = token() else { return (nil, nil, "not logged in to Claude Code") }
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        r.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        r.timeoutInterval = 15
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return (nil, nil, "offline") }
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { return (nil, nil, "HTTP \(h.statusCode)") }
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return (nil, nil, "unexpected reply") }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func lim(_ k: String) -> Limit? {
            guard let x = o[k] as? [String: Any], let p = x["utilization"] as? Double else { return nil }
            return Limit(pct: p, resets: (x["resets_at"] as? String).flatMap(f.date(from:)))
        }
        return (lim("five_hour"), lim("seven_day"), nil)
    }
}
