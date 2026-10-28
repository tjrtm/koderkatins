import Foundation

struct SessionInfo: Identifiable, Equatable {
    let id: String
    var project: String
    var title: String?
    var inputTokens = 0      // fresh input + cache writes
    var outputTokens = 0
    var cacheRead = 0
    var context = 0          // size of the latest request's prompt
    var lastActivity = Date.distantPast
    var working = false
    var turnEnded = false    // last turn finished; Claude is waiting for you
    var turnEndedAt: Date?
    var needsAttention = false
    var attentionMessage: String?
}

/// Reads Claude Code's local session logs incrementally and read-only.
///
/// Performance notes (this runs on laptops all day):
/// - files are stat'ed, and only opened when their size changed;
/// - new bytes are scanned as raw memory with memchr/memmem; only lines that contain one
///   of three markers are JSON-decoded;
/// - per-file progress and totals are cached on disk, so a relaunch doesn't re-read
///   hundreds of MB of history.
/// Only ever used from PetModel's private serial queue, so it needs no locking.
final class LogScanner: @unchecked Sendable {
    struct Usage: Codable, Equatable { var inp = 0, out = 0, cr = 0 }

    struct FileState: Codable {
        var offset: UInt64 = 0
        var inode: UInt64 = 0
        var totals = Usage()
        var lastID: String?          // streamed records of one message share an id: count it once
        var lastUsage = Usage()
        var carry = Data()           // partial last line
    }

    struct Meta: Codable {
        var title: String?
        var ctx = 0
        var ctxAt = Date.distantPast
        var lastTs = Date.distantPast
        var ended = false
        var endedAt: Date?
    }

    private struct Cache: Codable { var version = 2; var files: [String: FileState]; var meta: [String: Meta] }

    private var files: [String: FileState] = [:]
    private var meta: [String: Meta] = [:]
    private var dirty = false
    private var lastSave = Date.distantPast      // first scan saves right away
    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    private let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let needles: [[UInt8]] = ["\"usage\"", "\"ai-title\"", "\"turn_duration\""].map { Array($0.utf8) }
    private static let chunkSize = 1 << 20

    static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Koderkatins/scan-cache.json")
    }

    init(useCache: Bool = true) {
        guard useCache, let d = try? Data(contentsOf: Self.cacheURL),
              let c = try? JSONDecoder().decode(Cache.self, from: d), c.version == 2 else { return }
        files = c.files
        meta = c.meta
    }

    /// Persist progress (cheap: a few KB). Called after scans at most once a minute, and on quit.
    func save(force: Bool = false) {
        guard dirty, force || Date().timeIntervalSince(lastSave) > 60 else { return }
        let url = Self.cacheURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(Cache(files: files, meta: meta)) { try? d.write(to: url, options: .atomic) }
        dirty = false
        lastSave = Date()
    }

    func scan(activeWindow: TimeInterval) -> [SessionInfo] {
        let fm = FileManager.default
        let now = Date()
        var result: [SessionInfo] = []
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        for proj in projects {
            guard let items = try? fm.contentsOfDirectory(at: proj, includingPropertiesForKeys: Array(keys),
                                                          options: [.skipsHiddenFiles]) else { continue }
            for f in items where f.pathExtension == "jsonl" {
                let rv = try? f.resourceValues(forKeys: keys)
                let mod = rv?.contentModificationDate ?? .distantPast
                // sessions whose main log is old can't be active (subagents write the main log too)
                guard now.timeIntervalSince(mod) < activeWindow * 4 else { continue }
                let sid = f.deletingPathExtension().lastPathComponent
                var newest = mod
                var subs: [(URL, UInt64)] = []
                let subDir = proj.appendingPathComponent(sid).appendingPathComponent("subagents")
                if let s = try? fm.contentsOfDirectory(at: subDir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
                    for u in s where u.pathExtension == "jsonl" {
                        let v = try? u.resourceValues(forKeys: keys)
                        if let m = v?.contentModificationDate, m > newest { newest = m }
                        subs.append((u, UInt64(v?.fileSize ?? 0)))
                    }
                }
                guard now.timeIntervalSince(newest) < activeWindow else { continue }

                var total = read(f, session: sid, main: true, size: UInt64(rv?.fileSize ?? 0))
                for (u, size) in subs {
                    let t = read(u, session: sid, main: false, size: size)
                    total.inp += t.inp; total.out += t.out; total.cr += t.cr
                }
                let m = meta[sid] ?? Meta()
                var s = SessionInfo(id: sid, project: prettyProject(proj.lastPathComponent), title: m.title)
                s.inputTokens = total.inp; s.outputTokens = total.out; s.cacheRead = total.cr
                s.context = m.ctx
                s.lastActivity = max(newest, m.lastTs)
                s.turnEnded = m.ended
                s.turnEndedAt = m.endedAt
                s.working = !m.ended && now.timeIntervalSince(newest) < 30
                result.append(s)
            }
        }
        save()
        return result.sorted { $0.lastActivity > $1.lastActivity }
    }

    private func prettyProject(_ raw: String) -> String {
        let home = "-Users-" + NSUserName() + "-"
        var s = raw.hasPrefix(home) ? String(raw.dropFirst(home.count)) : raw
        if s.hasPrefix("-") { s.removeFirst() }
        return s.isEmpty ? "~" : s
    }

    /// Reads any new bytes of one log file and returns its running usage totals.
    private func read(_ url: URL, session: String, main: Bool, size: UInt64) -> Usage {
        let path = url.path
        var st = files[path] ?? FileState()
        if size > 0, size == st.offset { return st.totals }            // unchanged: don't open it

        var info = stat()
        guard stat(path, &info) == 0 else { return st.totals }
        let inode = UInt64(info.st_ino)
        if inode != st.inode || UInt64(info.st_size) < st.offset {        // new or rewritten file
            st = FileState(); st.inode = inode
        }
        let end = UInt64(info.st_size)
        guard end > st.offset, let h = FileHandle(forReadingAtPath: path) else { files[path] = st; return st.totals }
        defer { try? h.close() }
        try? h.seek(toOffset: st.offset)

        while st.offset < end {
            autoreleasepool {
                guard let chunk = try? h.read(upToCount: Self.chunkSize), !chunk.isEmpty else { st.offset = end; return }
                st.offset += UInt64(chunk.count)
                var buf = st.carry
                buf.append(chunk)
                let consumed = buf.withUnsafeBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return 0 }
                    let p = base.assumingMemoryBound(to: UInt8.self)
                    var start = 0
                    let n = raw.count
                    while start < n, let nlPtr = memchr(p + start, 0x0A, n - start) {
                        let nl = UnsafeRawPointer(nlPtr) - base
                        let len = nl - start
                        if len > 40 {
                            let line = UnsafeBufferPointer(start: p + start, count: len)
                            // Long lines are replies or tool output. Everything we need from them sits in the last
                            // few KB, so only look there and leave megabytes of content untouched. If a long line
                            // has no usage in its tail it carries nothing to count (fastUsage checks the shape and
                            // falls back to a full parse when unsure).
                            let probe = len > Self.window ? UnsafeBufferPointer(rebasing: line[(len - Self.window)...]) : line
                            if Self.find(probe, Self.needles[0]) != nil || (len > Self.window && Self.isAssistant(probe)) {
                                // usage records: read just the fields we need; fall back to full JSON if the shape is unexpected
                                if !fastUsage(line, session: session, main: main, state: &st) {
                                    parse(Data(line), session: session, main: main, state: &st)
                                }
                            } else if len <= Self.window, Self.find(line, Self.needles[1]) != nil || Self.find(line, Self.needles[2]) != nil {
                                parse(Data(line), session: session, main: main, state: &st)
                            }
                        }
                        start = nl + 1
                    }
                    return start
                }
                st.carry = buf.count > consumed ? buf.subdata(in: consumed..<buf.count) : Data()
                if st.carry.count > 64 << 20 { st.carry = Data() }      // pathological line: drop it
            }
        }
        files[path] = st
        dirty = true
        return st.totals
    }


    // MARK: fast path for assistant usage lines
    //
    // Assistant lines can be megabytes (they carry the whole reply), but we only need a few small fields.
    // In JSON, a key like "usage": can't appear unescaped inside a string value, so locating keys by
    // bytes is safe; `message.usage` and the record's own `type`/`timestamp` come after the content.

    private static let kType = Array("\"type\":\"".utf8)
    private static let kUsage = Array("\"usage\":{".utf8)
    private static let kMsgID = Array("\"message\":{\"id\":\"".utf8)
    private static let kMsgID2 = Array("\"id\":\"msg_".utf8)
    private static let kStop = Array("\"stop_reason\":".utf8)
    private static let kTime = Array("\"timestamp\":\"".utf8)

    static func find(_ b: UnsafeBufferPointer<UInt8>, _ needle: [UInt8], from: Int = 0) -> Int? {
        guard let base = b.baseAddress, from < b.count else { return nil }
        return needle.withUnsafeBufferPointer { n in
            memmem(base + from, b.count - from, n.baseAddress, n.count).map { UnsafeRawPointer($0) - UnsafeRawPointer(base) }
        }
    }

    static func findLast(_ b: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Int? {
        var at: Int? = nil, from = 0
        while let i = find(b, needle, from: from) { at = i; from = i + 1 }
        return at
    }

    /// The string value starting at `i` (just after the opening quote). Values we read never contain escapes.
    static func string(_ b: UnsafeBufferPointer<UInt8>, at i: Int) -> String? {
        var j = i
        while j < b.count, b[j] != 0x22 { if b[j] == 0x5C { return nil }; j += 1 }
        guard j < b.count else { return nil }
        return String(decoding: UnsafeBufferPointer(rebasing: b[i..<j]), as: UTF8.self)
    }

    /// Integer value of `"key":123` searched inside `b[range]`.
    static func int(_ b: UnsafeBufferPointer<UInt8>, _ key: String, in r: Range<Int>) -> Int {
        let k = Array("\"\(key)\":".utf8)
        let slice = UnsafeBufferPointer(rebasing: b[r])
        guard let i = find(slice, k) else { return 0 }
        var j = i + k.count, v = 0
        while j < slice.count, slice[j] >= 0x30, slice[j] <= 0x39 { v = v * 10 + Int(slice[j] - 0x30); j += 1 }
        return v
    }

    private static let window = 16 << 10
    private static let kAssistant = Array("\"type\":\"assistant\"".utf8)

    static func isAssistant(_ tail: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let ti = findLast(tail, kType) else { return false }
        return string(tail, at: ti + kType.count) == "assistant"
    }

    /// Last occurrence, looking in the line's tail first (cheap) and the whole line only if needed.
    static func findLastTailFirst(_ b: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Int? {
        if b.count > window {
            let off = b.count - window
            if let i = findLast(UnsafeBufferPointer(rebasing: b[off...]), needle) { return i + off }
        }
        return findLast(b, needle)
    }

    private func fastUsage(_ b: UnsafeBufferPointer<UInt8>, session: String, main: Bool, state st: inout FileState) -> Bool {
        // record type: the last "type":"…" belongs to the top-level object
        guard let ti = Self.findLastTailFirst(b, Self.kType) else { return false }
        let type = Self.string(b, at: ti + Self.kType.count)
        guard type == "assistant" else { return type != nil }            // user/tool lines: nothing to count
        guard let ui = Self.findLastTailFirst(b, Self.kUsage) else { return false }
        var depth = 0, end = ui + Self.kUsage.count - 1
        while end < b.count {
            if b[end] == 0x7B { depth += 1 } else if b[end] == 0x7D { depth -= 1; if depth == 0 { break } }
            end += 1
        }
        guard end < b.count else { return false }
        let r = ui..<end
        // nested objects (cache_creation, server_tool_use) hold other *_tokens keys: read the
        // top-level ones from before the first nested object, output_tokens from the whole object
        let body = ui + Self.kUsage.count
        let firstNested = Self.find(UnsafeBufferPointer(rebasing: b[body..<end]), [0x7B]).map { $0 + body } ?? end
        let top = ui..<firstNested
        let i = Self.int(b, "input_tokens", in: top)
        let cc = Self.int(b, "cache_creation_input_tokens", in: top)
        let cr = Self.int(b, "cache_read_input_tokens", in: top)
        var out = Self.int(b, "output_tokens", in: top)
        if out == 0 { out = Self.int(b, "output_tokens", in: r) }
        let head = UnsafeBufferPointer(rebasing: b[..<min(b.count, 4096)])
        let idAt = Self.find(head, Self.kMsgID2) ?? Self.find(b, Self.kMsgID2)
        let id = idAt.flatMap { Self.string(b, at: $0 + Self.kMsgID2.count - 4) }
        var stop: String?
        if let si = Self.findLastTailFirst(b, Self.kStop), si + Self.kStop.count < b.count, b[si + Self.kStop.count] == 0x22 {
            stop = Self.string(b, at: si + Self.kStop.count + 1)
        }
        let ts = Self.findLastTailFirst(b, Self.kTime).flatMap { Self.date(b, at: $0 + Self.kTime.count) }
        record(Usage(inp: i + cc, out: out, cr: cr), id: id, stop: stop, ts: ts, session: session, main: main, state: &st)
        return true
    }

    /// Parses "2026-10-28T12:34:56.789Z" without ICU (DateFormatter is ~50× slower).
    static func date(_ b: UnsafeBufferPointer<UInt8>, at i: Int) -> Date? {
        guard i + 20 <= b.count, b[i + 4] == 0x2D, b[i + 10] == 0x54 else { return nil }
        func n(_ o: Int, _ len: Int) -> Int? {
            var v = 0
            for k in o..<(o + len) { let c = b[i + k]; guard c >= 0x30, c <= 0x39 else { return nil }; v = v * 10 + Int(c - 0x30) }
            return v
        }
        guard let y = n(0, 4), let mo = n(5, 2), let d = n(8, 2), let h = n(11, 2), let mi = n(14, 2), let s = n(17, 2) else { return nil }
        var frac = 0.0, k = i + 19
        if k < b.count, b[k] == 0x2E {
            var scale = 0.1; k += 1
            while k < b.count, b[k] >= 0x30, b[k] <= 0x39 { frac += Double(b[k] - 0x30) * scale; scale /= 10; k += 1 }
        }
        guard k < b.count, b[k] == 0x5A else { return nil }            // only UTC "Z" timestamps (what Claude Code writes)
        // days from civil (Howard Hinnant)
        let yy = mo <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        return Date(timeIntervalSince1970: Double(days * 86400 + h * 3600 + mi * 60 + s) + frac)
    }

    private func record(_ usage: Usage, id: String?, stop: String?, ts: Date?, session: String, main: Bool, state st: inout FileState) {
        if let id, id == st.lastID {                     // another record of the same message: replace, don't add
            st.totals.inp += usage.inp - st.lastUsage.inp
            st.totals.out += usage.out - st.lastUsage.out
            st.totals.cr += usage.cr - st.lastUsage.cr
        } else {
            st.totals.inp += usage.inp; st.totals.out += usage.out; st.totals.cr += usage.cr
        }
        st.lastID = id
        st.lastUsage = usage
        var m = meta[session] ?? Meta()
        if let ts, ts > m.lastTs { m.lastTs = ts }
        if main {
            if stop == "end_turn" { m.ended = true; m.endedAt = ts ?? Date() } else { m.ended = false; m.endedAt = nil }
            if let ts, ts >= m.ctxAt { m.ctx = usage.inp + usage.cr; m.ctxAt = ts }
        }
        meta[session] = m
    }

    private func parse(_ line: Data, session: String, main: Bool, state st: inout FileState) {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        let type = o["type"] as? String
        let ts = (o["timestamp"] as? String).flatMap(iso.date(from:))
        if type == "assistant", let msg = o["message"] as? [String: Any], let u = msg["usage"] as? [String: Any] {
            let i = u["input_tokens"] as? Int ?? 0
            let cc = u["cache_creation_input_tokens"] as? Int ?? 0
            let cr = u["cache_read_input_tokens"] as? Int ?? 0
            let out = u["output_tokens"] as? Int ?? 0
            record(Usage(inp: i + cc, out: out, cr: cr), id: msg["id"] as? String, stop: msg["stop_reason"] as? String,
                   ts: ts, session: session, main: main, state: &st)
            return
        }
        var m = meta[session] ?? Meta()
        if let ts, ts > m.lastTs { m.lastTs = ts }
        if type == "ai-title", let t = o["aiTitle"] as? String, !t.isEmpty { m.title = t }
        if main, type == "system", (o["subtype"] as? String) == "turn_duration" { m.ended = true; m.endedAt = ts ?? Date() }
        meta[session] = m
    }

    /// Number of live Claude Code CLI processes (each registers ~/.claude/sessions/<pid>.json).
    static func runningProcesses() -> Int {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { Int32($0.dropLast(5)) }.filter { kill($0, 0) == 0 }.count
    }
}

/// Optional, exact "needs attention" signals written by a Claude Code Notification hook
/// (see README). Each file is one hook payload; it is consumed and deleted.
enum Signals {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Koderkatins/signals", isDirectory: true)
    }

    struct Signal { let session: String?; let message: String?; let event: String? }

    static func drain() -> [Signal] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil), !files.isEmpty else { return [] }
        var out: [Signal] = []
        for f in files.prefix(50) {
            defer { try? fm.removeItem(at: f) }
            guard let d = try? Data(contentsOf: f), d.count < 65_536 else { continue }
            let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            out.append(Signal(session: o?["session_id"] as? String,
                              message: o?["message"] as? String,
                              event: o?["hook_event_name"] as? String))
        }
        return out
    }
}

/// Calls `onChange` on the main queue (coalesced by FSEvents latency) when anything under `path` changes.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(path: String, latency: TimeInterval = 1.0, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        stream = FSEventStreamCreate(nil, cb, &ctx, [path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
