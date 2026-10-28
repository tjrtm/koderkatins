import AppKit
import QuartzCore

/// Plays the pet's frames with Core Animation.
///
/// Why AppKit instead of SwiftUI here: a SwiftUI frame swap re-runs view diffing every frame, and
/// a SwiftUI cross-fade animates at the display refresh rate inside our process (measured ≈1.5 % CPU).
/// Setting `layer.contents` with a `CATransition` hands the fade to the window server, so per-frame
/// cost in this app is one timer callback and a pointer swap.
final class SpritePlayerView: NSView {
    var sprite: Sprite? { didSet { if sprite !== oldValue { idx = 0; render(animated: false); report() } } }
    var scale: CGFloat = 0.5 { didSet { if scale != oldValue { render(animated: false); report() } } }
    var frameDuration: Double = 0.3 { didSet { if frameDuration != oldValue { restUntil = .distantPast; restartTimer() } } }
    var restSeconds: Double = 2 { didSet { if restSeconds != oldValue { restUntil = .distantPast; report() } } }
    var motion = 1 { didSet { if motion != oldValue { restUntil = .distantPast; report() } } }   // 0 still 1 calm 2 normal 3 lively 4 custom
    var smooth = true { didSet { if smooth != oldValue { report() } } }
    var paused = false { didSet { if paused != oldValue { restartTimer() } } }
    var mood: () -> PetMood = { .idle }

    private var timer: Timer?
    private var idx = 0
    private var shownMood: PetMood = .idle
    private var restUntil = Date.distantPast
    private var halfStep = false
    private var occluded = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .trilinear
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }      // SwiftUI handles clicks/drags

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let w = window {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: w)
        }
        restartTimer()
        render(animated: false)
    }

    @objc private func occlusionChanged() {
        occluded = !(window?.occlusionState.contains(.visible) ?? true)
        restartTimer()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render(animated: false)
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard window != nil, !paused, !occluded else { return }
        let t = Timer(timeInterval: frameDuration, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
            if Debug.on, self.advances % 5 == 0 { self.report() }
        }
        t.tolerance = frameDuration * 0.25     // lets macOS coalesce wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
        report()
    }

    private func tick() {
        let mood = mood()
        let urgent = mood == .attention || mood == .done
        if motion == 0 && !urgent {                                  // Still
            if shownMood != mood || idx != 0 { shownMood = mood; idx = 0; render(animated: smooth) }
            return
        }
        if Date() < restUntil && !urgent { return }
        if shownMood == .idle || shownMood == .sleepy {             // calm moods at half speed
            halfStep.toggle()
            if halfStep { return }
        }
        let count = frames().count
        let next = count > 0 ? (idx + 1) % count : 0
        if next == 0 {
            if mood != shownMood { shownMood = mood }               // change animation only at loop end
            if restSeconds > 0 && !urgent { restUntil = Date().addingTimeInterval(restSeconds) }
        }
        if next == idx && count <= 1 { return }
        idx = next
        render(animated: smooth)
        advances += 1
    }

    private var advances = 0
    /// Opt-in diagnostics (KODERKATINS_DEBUG=1): what the player is actually doing.
    private func report() {
        guard Debug.on else { return }
        Debug.set("player", [
            "frameDuration": frameDuration, "restSeconds": restSeconds, "motion": motion, "smooth": smooth,
            "scale": Double(scale), "paused": paused, "occluded": occluded,
            "timerInterval": timer?.timeInterval ?? 0, "sprite": sprite?.name ?? "-",
            "pixelWidth": Int((sprite?.frameSize.width ?? 0) * scale * (window?.backingScaleFactor ?? 2)),
            "shownMood": shownMood.rawValue, "frameAdvances": advances,
        ])
    }

    private func frames() -> [CGImage] {
        guard let sprite else { return [] }
        let px = Int((sprite.frameSize.width * scale * (window?.backingScaleFactor ?? 2)).rounded())
        return sprite.frames(shownMood, pixelWidth: px)
    }

    private func render(animated: Bool) {
        let f = frames()
        guard !f.isEmpty, let layer else { return }
        let img = f[idx % f.count]
        if (layer.contents as AnyObject?) === img { return }
        CATransaction.begin()
        if animated {
            let t = CATransition()
            t.type = .fade
            t.duration = min(0.15, frameDuration * 0.5)
            layer.add(t, forKey: "frame")
        } else {
            CATransaction.setDisableActions(true)
        }
        layer.contents = img
        layer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self) }
}
