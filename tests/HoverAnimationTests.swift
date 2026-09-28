import Foundation
import ImageIO

@main
struct HoverAnimationTests {
    static var assertions = 0

    static func require(_ condition: @autoclosure () -> Bool, _ description: String) {
        assertions += 1
        guard condition() else { fatalError("FAIL: \(description)") }
    }

    static func main() {
        let timeline = HoverAnimationTimeline(frameDurations: [0.25, 0.5, 0.25])
        require(timeline.representativeFrame == 1, "starts at representative frame")
        require(timeline.initialOffset == 0.25, "representative frame start time")
        require(timeline.duration == 1, "total duration")
        require(timeline.position(at: 0)?.frame == 1, "initial frame is not black first frame")
        require(timeline.position(at: 0.49)?.frame == 1, "respects per-frame delay")
        require(timeline.position(at: 0.5)?.frame == 2, "advances at exact frame boundary")
        require(timeline.position(at: 0.75)?.frame == 0, "wraps to the first frame")
        require(timeline.position(at: 1)?.frame == 1, "one complete loop")
        require(timeline.position(at: 10_001.5)?.frame == 2, "large elapsed time skips missed cycles")
        require(timeline.position(at: -1)?.frame == 1, "negative time is clamped")
        require(timeline.position(at: .infinity)?.frame == 1, "infinite time is sanitized")
        require(timeline.position(at: .nan)?.frame == 1, "NaN time is sanitized")
        require(timeline.position(at: 0)?.remaining == 0.5, "remaining representative frame delay")
        let laterStart = HoverAnimationTimeline(frameDurations: [0.25, 0.5, 0.25], representativeFrame: 2)
        require(laterStart.representativeFrame == 2 && laterStart.initialOffset == 0.75, "explicit two-thirds start")
        require(laterStart.position(at: 0)?.frame == 2, "two-thirds frame displays immediately")
        require(laterStart.position(at: 0.25)?.frame == 0, "two-thirds preview still wraps to first frame")
        require(HoverAnimationTimeline(frameDurations: [0.1, 0.1], representativeFrame: -1).representativeFrame == 0,
                "negative representative frame is clamped")
        require(HoverAnimationTimeline(frameDurations: [0.1, 0.1], representativeFrame: 99).representativeFrame == 1,
                "out-of-range representative frame is clamped")
        let empty = HoverAnimationTimeline(frameDurations: [])
        require(empty.position(at: 1) == nil, "empty GIF has no schedule")
        let single = HoverAnimationTimeline(frameDurations: [0.125])
        require(single.representativeFrame == 0 && single.position(at: 100)?.frame == 0, "single-frame GIF")
        let malformed = HoverAnimationTimeline(frameDurations: [0, -1, .nan, .infinity, 0.001, 1e300])
        require(malformed.duration.isFinite && abs(malformed.duration - 60.41) < 0.000001, "invalid and excessive delays are bounded")
        require(malformed.position(at: 1e300) != nil, "large finite elapsed is bounded")

        if CommandLine.arguments.count > 1 {
            for name in ["PS1Startup", "PS2Startup"] {
                let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".gif")
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { fatalError("Missing \(name)") }
                let count = CGImageSourceGetCount(source)
                require(count > 1, "\(name) contains multiple frames")
                let initialFrame = name == "PS1Startup" ? count * 2 / 3 : count / 3
                require(CGImageSourceCreateImageAtIndex(source, initialFrame, nil) != nil, "\(name) representative frame decodes")
                var durations: [TimeInterval] = []
                for index in 0..<count {
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                    let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    durations.append((gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                        ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1)
                }
                let actual = HoverAnimationTimeline(frameDurations: durations, representativeFrame: initialFrame)
                require(actual.position(at: 0)?.frame == initialFrame, "\(name) starts with the verified representative frame")
                var starts: [TimeInterval] = [0]
                starts.append(contentsOf: actual.frameEnds.dropLast())
                for index in 0..<count {
                    // Sample inside each frame rather than at a floating-point boundary.
                    let midpoint = (starts[index] + actual.frameEnds[index]) / 2
                    let elapsed = (midpoint - actual.initialOffset + actual.duration)
                        .truncatingRemainder(dividingBy: actual.duration)
                    require(actual.position(at: elapsed)?.frame == index, "\(name) visits frame \(index)")
                }
                print("\(name): \(count) frames, \(String(format: "%.2f", actual.duration)) seconds, representative \(actual.representativeFrame)")
            }
        }
        print("PASS: \(assertions) hover-animation assertions")
    }
}
