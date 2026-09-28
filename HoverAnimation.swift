import AppKit
import ImageIO
import SwiftUI

/// A bounded, wall-clock timeline: missed frames are skipped instead of queued.
/// The preview starts on a representative frame, then loops through the whole GIF.
struct HoverAnimationTimeline {
    let frameEnds: [TimeInterval]
    let representativeFrame: Int
    let initialOffset: TimeInterval
    let duration: TimeInterval

    init(frameDurations: [TimeInterval], representativeFrame requestedFrame: Int? = nil) {
        var ends: [TimeInterval] = []
        var cumulative: TimeInterval = 0
        for declared in frameDurations {
            let delay = declared.isFinite && declared > 0 ? max(0.01, declared) : 0.1
            cumulative += min(delay, 60)
            ends.append(cumulative)
        }
        frameEnds = ends
        representativeFrame = frameDurations.isEmpty ? 0
            : min(frameDurations.count - 1, max(0, requestedFrame ?? frameDurations.count / 3))
        initialOffset = representativeFrame == 0 ? 0 : ends[representativeFrame - 1]
        duration = cumulative
    }

    func position(at elapsed: TimeInterval) -> (frame: Int, remaining: TimeInterval)? {
        guard !frameEnds.isEmpty, duration > 0 else { return nil }
        let safeElapsed = elapsed.isFinite ? max(0, elapsed) : 0
        let position = (safeElapsed.truncatingRemainder(dividingBy: duration) + initialOffset)
            .truncatingRemainder(dividingBy: duration)
        var lower = 0
        var upper = frameEnds.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            if frameEnds[middle] > position { upper = middle } else { lower = middle + 1 }
        }
        return (lower, max(0.001, frameEnds[lower] - position))
    }
}

/// Decorative, silent preview only. This view never launches an emulator.
@MainActor
struct HoverAnimationView: NSViewRepresentable {
    let resourceName: String
    let reducedMotion: Bool

    func makeNSView(context: Context) -> HoverAnimationNSView {
        let view = HoverAnimationNSView(frame: .zero)
        view.configure(resourceName: resourceName, reducedMotion: reducedMotion)
        return view
    }

    func updateNSView(_ nsView: HoverAnimationNSView, context: Context) {
        nsView.configure(resourceName: resourceName, reducedMotion: reducedMotion)
    }

    static func dismantleNSView(_ nsView: HoverAnimationNSView, coordinator: ()) {
        nsView.cancel()
    }
}

@MainActor
final class HoverAnimationNSView: NSView {
    private var resourceName = ""
    private var reducedMotion = false
    private var configured = false
    private var source: CGImageSource?
    private var timeline = HoverAnimationTimeline(frameDurations: [])
    private var displayedFrame = -1
    private var image: CGImage?
    private var elapsedBeforePause: TimeInterval = 0
    private var startedAt: TimeInterval?
    private var timer: Timer?

    override var isOpaque: Bool { true }

    func configure(resourceName: String, reducedMotion: Bool) {
        guard !configured || self.resourceName != resourceName || self.reducedMotion != reducedMotion else { return }
        cancel()
        configured = true
        self.resourceName = resourceName
        self.reducedMotion = reducedMotion

        let name = (resourceName as NSString).deletingPathExtension
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        if let url = Bundle.main.url(forResource: name, withExtension: "gif"),
           let source = CGImageSourceCreateWithURL(url as CFURL, options) {
            let count = CGImageSourceGetCount(source)
            if count > 0 {
                var durations: [TimeInterval] = []
                durations.reserveCapacity(count)
                for index in 0..<count {
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                    let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    let unclamped = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                    let clamped = (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                    durations.append(unclamped ?? clamped ?? 0.1)
                }
                self.source = source
                // PS1's middle section is a white fade; its classic logo appears
                // at two thirds. PS2's first third already shows the blue towers.
                let initialFrame = resourceName.localizedCaseInsensitiveContains("PS1") ? count * 2 / 3 : count / 3
                timeline = HoverAnimationTimeline(frameDurations: durations, representativeFrame: initialFrame)
                showFrame(timeline.representativeFrame)
            }
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Prévia do \(consoleName)")
        needsDisplay = true
        resumeIfVisible()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if let startedAt {
                elapsedBeforePause += max(0, ProcessInfo.processInfo.systemUptime - startedAt)
            }
            startedAt = nil
            cancelTimer()
        } else {
            resumeIfVisible()
        }
    }

    private var consoleName: String {
        resourceName.localizedCaseInsensitiveContains("PS1") ? "PlayStation" : "PlayStation 2"
    }

    private func resumeIfVisible() {
        guard configured, window != nil, !reducedMotion, source != nil,
              timeline.frameEnds.count > 1, startedAt == nil else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        advance()
    }

    private func advance() {
        guard configured, window != nil, !reducedMotion, source != nil, let startedAt else { return }
        let elapsed = elapsedBeforePause + max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        guard let position = timeline.position(at: elapsed), showFrame(position.frame) else { return }
        cancelTimer()
        // The run loop retains the timer, but the timer must not retain its NSView.
        let next = Timer(timeInterval: position.remaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                self?.advance()
            }
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    @discardableResult
    private func showFrame(_ index: Int) -> Bool {
        guard index != displayedFrame else { return image != nil }
        guard let source,
              let decoded = CGImageSourceCreateImageAtIndex(source, index,
                  [kCGImageSourceShouldCache: false] as CFDictionary) else {
            // A broken resource remains a harmless static preview, with no retry loop.
            cancelTimer()
            self.source = nil
            startedAt = nil
            return false
        }
        displayedFrame = index
        image = decoded
        needsDisplay = true
        return true
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    func cancel() {
        cancelTimer()
        configured = false
        startedAt = nil
        elapsedBeforePause = 0
        source = nil
        image = nil
        displayedFrame = -1
        timeline = HoverAnimationTimeline(frameDurations: [])
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if let image, let context = NSGraphicsContext.current?.cgContext {
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            let scale = min(bounds.width / width, bounds.height / height)
            let rect = CGRect(x: bounds.midX - width * scale / 2,
                              y: bounds.midY - height * scale / 2,
                              width: width * scale, height: height * scale)
            context.interpolationQuality = .high
            context.draw(image, in: rect)
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: min(30, max(16, bounds.width / 12)), weight: .light),
                .foregroundColor: NSColor.white
            ]
            let title = consoleName as NSString
            let size = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
