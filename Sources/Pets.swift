import AppKit

/// Row of the petdex sheet used for each mood.
enum PetMood: Int {
    case idle = 0, attention = 3, done = 4, worried = 5, thinking = 6, working = 7, sleepy = 8

    /// Used when a pet has no art for this mood.
    var fallbacks: [PetMood] {
        switch self {
        case .worried: return [.sleepy, .idle]
        case .sleepy: return [.idle]
        case .thinking: return [.working, .idle]
        default: return [.idle]
        }
    }
}

struct PetEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let sheet: URL
    let builtIn: Bool
}

/// Finds pets in the app bundle and in ~/Library/Application Support/Koderkatins/Pets.
/// A pet is a folder with spritesheet.webp/.png and an optional pet.json (petdex format).
enum PetLibrary {
    static var userDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Koderkatins/Pets", isDirectory: true)
    }

    static func all() -> [PetEntry] {
        var out: [PetEntry] = []
        if let b = Bundle.main.resourceURL?.appendingPathComponent("Pets") { out += scan(b, builtIn: true) }
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        out += scan(userDir, builtIn: false)
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    private static func scan(_ dir: URL, builtIn: Bool) -> [PetEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items.compactMap { folder -> PetEntry? in
            var sheetName = "spritesheet.webp"
            var name = folder.lastPathComponent
            if let d = try? Data(contentsOf: folder.appendingPathComponent("pet.json")),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                name = (o["displayName"] as? String) ?? name
                sheetName = (o["spritesheetPath"] as? String) ?? sheetName
            }
            let candidates = [sheetName, "spritesheet.webp", "spritesheet.png"].map { folder.appendingPathComponent($0) }
            guard let sheet = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else { return nil }
            return PetEntry(id: (builtIn ? "" : "user:") + folder.lastPathComponent, name: name, sheet: sheet, builtIn: builtIn)
        }.sorted { $0.name < $1.name }
    }
}

/// A petdex sprite sheet: 8 columns × 9 rows of equally sized frames.
final class Sprite {
    let name: String
    private var rows: [[CGImage]] = []
    private var cache: [Int: [CGImage]] = [:]
    private var cachePixelWidth = 0
    let frameSize: NSSize

    init?(url: URL) {
        name = url.deletingLastPathComponent().lastPathComponent
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let cols = 8, rowsN = 9, w = cg.width / cols, h = cg.height / rowsN
        frameSize = NSSize(width: w, height: h)
        for r in 0..<rowsN {
            var frames: [CGImage] = []
            for c in 0..<cols {
                guard let sub = cg.cropping(to: CGRect(x: c * w, y: r * h, width: w, height: h)), !Sprite.isEmpty(sub) else { continue }
                frames.append(sub)
            }
            rows.append(frames)
        }
        if rows.allSatisfy({ $0.isEmpty }) { return nil }
    }

    /// Frames for a mood, rendered once at the exact on-screen pixel size (no per-frame scaling).
    func frames(_ mood: PetMood, pixelWidth: Int) -> [CGImage] {
        if pixelWidth != cachePixelWidth { cache.removeAll(); cachePixelWidth = pixelWidth }
        let row = resolvedRow(mood)
        if let c = cache[row] { return c }
        let src = rows.indices.contains(row) ? rows[row] : []
        let pw = max(8, pixelWidth)
        let ph = Int((Double(pw) * frameSize.height / frameSize.width).rounded())
        let out: [CGImage] = src.compactMap { cg in
            guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pw, height: ph))
            return ctx.makeImage()
        }
        cache[row] = out
        return out
    }

    private func resolvedRow(_ mood: PetMood) -> Int {
        for m in [mood] + mood.fallbacks where rows.indices.contains(m.rawValue) && !rows[m.rawValue].isEmpty { return m.rawValue }
        return rows.firstIndex { !$0.isEmpty } ?? 0
    }

    private static func isEmpty(_ cg: CGImage) -> Bool {
        let w = 24, h = 26
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return !stride(from: 3, to: buf.count, by: 4).contains { buf[$0] > 8 }
    }


}
