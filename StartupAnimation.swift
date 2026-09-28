import AppKit
import ImageIO
import SwiftUI

/// Plays one pass of a bundled GIF. Parent view updates only refresh the callback;
/// they do not restart the animation unless its resource or motion setting changes.
@MainActor
struct StartupAnimationView: NSViewRepresentable {
    let resourceName: String
    let reducedMotion: Bool
    let onComplete: @MainActor () -> Void

    func makeNSView(context: Context) -> StartupAnimationNSView {
        let view = StartupAnimationNSView(frame: .zero)
        view.configure(resourceName: resourceName, reducedMotion: reducedMotion, onComplete: onComplete)
        return view
    }

    func updateNSView(_ nsView: StartupAnimationNSView, context: Context) {
        nsView.configure(resourceName: resourceName, reducedMotion: reducedMotion, onComplete: onComplete)
    }

    static func dismantleNSView(_ nsView: StartupAnimationNSView, coordinator: ()) {
        nsView.cancel()
    }
}

@MainActor
final class StartupAnimationNSView: NSView {
    private var resourceName = ""
    private var reducedMotion = false
    private var configured = false
    private var completed = false
    private var onComplete: (@MainActor () -> Void)?
    private var source: CGImageSource?
    private var frameEnds: [TimeInterval] = []
    private var displayedFrame = -1
    private var image: CGImage?
    private var totalDuration: TimeInterval = 1
    private var elapsedBeforePause: TimeInterval = 0
    private var startedAt: TimeInterval?
    private var timer: Timer?
    private var fallback = false

    override var isOpaque: Bool { true }

    func configure(resourceName: String, reducedMotion: Bool, onComplete: @escaping @MainActor () -> Void) {
        self.onComplete = onComplete
        guard !configured || self.resourceName != resourceName || self.reducedMotion != reducedMotion else { return }
        cancelTimer()
        configured = true
        self.resourceName = resourceName
        self.reducedMotion = reducedMotion
        completed = false
        elapsedBeforePause = 0
        startedAt = nil
        displayedFrame = -1
        source = nil
        image = nil
        frameEnds = []
        totalDuration = 1
        fallback = false

        let name = (resourceName as NSString).deletingPathExtension
        if let url = Bundle.main.url(forResource: name, withExtension: "gif"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetCount(source) > 0 {
            self.source = source
            let count = CGImageSourceGetCount(source)
            if reducedMotion {
                // The first frame is often black: use a representative still.
                displayedFrame = count / 3
                image = CGImageSourceCreateImageAtIndex(source, displayedFrame, nil)
                if image == nil { useFallback() }
            } else {
                var cumulative: TimeInterval = 0
                for index in 0..<count {
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                    let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    let unclamped = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                    let clamped = (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                    let declared = unclamped ?? clamped ?? 0.1
                    let duration = declared.isFinite && declared > 0 ? declared : 0.1
                    cumulative += duration
                    frameEnds.append(cumulative)
                }
                totalDuration = cumulative
                displayedFrame = 0
                image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                if image == nil { useFallback() }
            }
        } else {
            useFallback()
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Inicialização do \(consoleName)")
        needsDisplay = true
        if window != nil { resume() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if let startedAt {
                elapsedBeforePause += ProcessInfo.processInfo.systemUptime - startedAt
            }
            startedAt = nil
            cancelTimer()
        } else {
            resume()
        }
    }

    private var consoleName: String {
        resourceName.localizedCaseInsensitiveContains("PS1") ? "PlayStation" : "PlayStation 2"
    }

    private func useFallback() {
        fallback = true
        source = nil
        image = nil
        frameEnds = []
        displayedFrame = -1
        totalDuration = 1
        elapsedBeforePause = 0
        startedAt = nil
    }

    private func resume() {
        guard configured, !completed, startedAt == nil else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        advance()
    }

    @objc private func timerFired(_ timer: Timer) {
        self.timer = nil
        advance()
    }

    private func advance() {
        guard !completed, window != nil, let startedAt else { return }
        let elapsed = elapsedBeforePause + ProcessInfo.processInfo.systemUptime - startedAt
        guard elapsed < totalDuration else {
            completed = true
            self.startedAt = nil
            cancelTimer()
            let completion = onComplete
            onComplete = nil
            completion?()
            return
        }

        var nextBoundary = totalDuration
        if !reducedMotion, !fallback, let source,
           let index = frameEnds.firstIndex(where: { $0 > elapsed }) {
            if index != displayedFrame {
                guard let decoded = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                    // A corrupt later frame must not leave the launch overlay stuck.
                    useFallback()
                    self.startedAt = ProcessInfo.processInfo.systemUptime
                    needsDisplay = true
                    schedule(after: 1)
                    return
                }
                displayedFrame = index
                image = decoded
                needsDisplay = true
            }
            nextBoundary = frameEnds[index]
        }
        schedule(after: max(0.001, nextBoundary - elapsed))
    }

    private func schedule(after interval: TimeInterval) {
        cancelTimer()
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(timerFired(_:)), userInfo: nil, repeats: false)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    func cancel() {
        cancelTimer()
        completed = true
        startedAt = nil
        onComplete = nil
        source = nil
        image = nil
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
                .font: NSFont.systemFont(ofSize: min(54, max(20, bounds.width / 12)), weight: .light),
                .foregroundColor: NSColor.white
            ]
            let title = consoleName as NSString
            let size = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
