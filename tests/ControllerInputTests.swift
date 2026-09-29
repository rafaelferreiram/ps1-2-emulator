import Foundation

@main
struct ControllerInputTests {
    static var assertions = 0
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard value() else { fatalError("FAIL: \(message)") }
    }
    static func ready(_ context: String = "menu") -> AnalogNavigation {
        var stick = AnalogNavigation()
        require(stick.sample(x: 0, y: 0, time: 0, context: context, repeats: false) == nil, "neutral arms without movement")
        return stick
    }
    static func main() {
        for (x, y, expected): (Float, Float, AnalogNavigation.Direction) in [
            (-1, 0, .left), (1, 0, .right), (0, 1, .up), (0, -1, .down)
        ] {
            var stick = ready()
            require(stick.sample(x: x, y: y, time: 1, context: "menu", repeats: false) == expected, "all four directions map correctly")
            for tick in 1...60 {
                require(stick.sample(x: x, y: y, time: 1 + Double(tick), context: "menu", repeats: false) == nil, "holding on menu never oscillates consoles")
            }
            require(stick.sample(x: 0, y: 0, time: 70, context: "menu", repeats: false) == nil, "release does not move")
            require(stick.sample(x: x, y: y, time: 71, context: "menu", repeats: false) == expected, "neutral permits a new gesture")
        }
        var drift = ready()
        for x: Float in [-0.54, -0.3, 0, 0.3, 0.54] {
            for y: Float in [-0.54, -0.3, 0, 0.3, 0.54] {
                require(drift.sample(x: x, y: y, time: 1, context: "menu", repeats: false) == nil, "sub-threshold noise never moves")
            }
        }
        require(drift.sample(x: 0.55, y: 0, time: 2, context: "menu", repeats: false) == .right, "activation threshold is inclusive")
        for x: Float in [0.54, 0.56, 0.32, 0.7] {
            require(drift.sample(x: x, y: 0, time: 3, context: "menu", repeats: false) == nil, "hysteresis prevents threshold chatter")
        }
        require(drift.sample(x: 0.30, y: 0, time: 4, context: "menu", repeats: false) == nil, "release threshold is inclusive")
        require(drift.sample(x: 0.8, y: 0, time: 5, context: "menu", repeats: false) == .right, "release rearms direction")

        var diagonal = ready()
        require(diagonal.sample(x: 0.8, y: 0.8, time: 1, context: "menu", repeats: false) == .right, "diagonal emits just one axis")
        require(diagonal.sample(x: 0.77, y: 0.82, time: 2, context: "menu", repeats: false) == nil, "small diagonal variation keeps axis")
        require(diagonal.sample(x: 0.6, y: 0.95, time: 3, context: "menu", repeats: false) == .up, "deliberate dominant-axis change moves")
        require(diagonal.sample(x: 0, y: -1, time: 4, context: "menu", repeats: false) == .down, "full reversal responds immediately")

        var repeating = ready("catalog-ps2")
        require(repeating.sample(x: 1, y: 0, time: 1, context: "catalog-ps2", repeats: true) == .right, "catalog gesture moves immediately")
        require(repeating.sample(x: 1, y: 0, time: 1.44, context: "catalog-ps2", repeats: true) == nil, "catalog waits initial delay")
        require(repeating.sample(x: 1, y: 0, time: 1.46, context: "catalog-ps2", repeats: true) == .right, "catalog repeats after delay")
        require(repeating.sample(x: 1, y: 0, time: 1.59, context: "catalog-ps2", repeats: true) == nil, "repetition is rate limited")
        require(repeating.sample(x: 1, y: 0, time: 1.61, context: "catalog-ps2", repeats: true) == .right, "subsequent repetition works")
        require(repeating.sample(x: 1, y: 0, time: 100, context: "catalog-ps2", repeats: true) == .right, "late timer emits one step")
        require(repeating.sample(x: 1, y: 0, time: 100, context: "catalog-ps2", repeats: true) == nil, "no catch-up burst")
        require(repeating.sample(x: 0, y: 0, time: 101, context: "catalog-ps2", repeats: true) == nil, "neutral stops repeats")

        for blockedContext: String? in [nil, "menu", "catalog-ps1"] {
            var transition = ready("catalog-ps2")
            _ = transition.sample(x: 1, y: 0, time: 1, context: "catalog-ps2", repeats: true)
            require(transition.sample(x: 1, y: 0, time: 2, context: blockedContext, repeats: true) == nil, "focus or screen change blocks held input")
            require(transition.sample(x: 1, y: 0, time: 3, context: "catalog-ps2", repeats: true) == nil, "returning does not replay held input")
            _ = transition.sample(x: 0, y: 0, time: 4, context: "catalog-ps2", repeats: true)
            require(transition.sample(x: 1, y: 0, time: 5, context: "catalog-ps2", repeats: true) == .right, "fresh gesture works after return")
        }
        var connection = AnalogNavigation()
        require(connection.sample(x: -1, y: 0, time: 1, context: "menu", repeats: false) == nil, "connecting with stick held does not move")
        _ = connection.sample(x: 0, y: 0, time: 2, context: "menu", repeats: false)
        require(connection.sample(x: -1, y: 0, time: 3, context: "menu", repeats: false) == .left, "connected stick works after neutral")
        connection.suspend()
        require(connection.sample(x: -1, y: 0, time: 4, context: "menu", repeats: false) == nil, "button action suspends held stick")
        _ = connection.sample(x: 0, y: 0, time: 5, context: "menu", repeats: false)
        require(connection.sample(x: 1, y: 0, time: 6, context: "menu", repeats: false) == .right, "button at neutral allows next gesture")
        var screens = AnalogNavigation()
        _ = screens.sample(x: 0, y: 0, time: 0, context: nil, repeats: false)
        for screen in ["menu", "catalog-ps1", "catalog-ps2", "menu"] {
            require(screens.sample(x: 0, y: 0, time: 1, context: screen, repeats: false) == nil, "screen observer rearms centered stick")
            require(screens.sample(x: 0.8, y: 0, time: 2, context: screen, repeats: false) == .right, "first gesture after boot or screen change responds")
        }
        for invalid: Float in [.nan, .infinity, -.infinity] {
            var stick = ready()
            require(stick.sample(x: invalid, y: 1, time: 1, context: "menu", repeats: false) == nil, "invalid axis cannot navigate")
            require(stick.sample(x: 1, y: 0, time: 2, context: "menu", repeats: false) == nil, "invalid sample requires neutral recovery")
        }
        var chord = TriggerChord()
        require(!chord.update(left: true, right: nil), "L2 alone does not reload")
        require(chord.update(left: nil, right: true), "adding R2 completes the chord once")
        require(!chord.update(left: true, right: true), "holding R2+L2 does not repeat")
        require(!chord.update(left: nil, right: false), "releasing one trigger stays disarmed")
        require(!chord.update(left: nil, right: true), "pressing the released trigger again does not reload")
        require(!chord.update(left: false, right: false), "releasing both rearms without firing")
        require(chord.update(left: true, right: true), "a fresh R2+L2 reloads")
        var held = TriggerChord()
        held.adopt(left: true, right: true)
        require(!held.update(left: true, right: true), "triggers already held at connection do not reload")
        require(!held.update(left: false, right: false), "releasing the connected hold rearms")
        require(held.update(left: true, right: true), "the next deliberate chord reloads")
        print("PASS: \(assertions) analog direction, dead-zone, repeat and lifecycle assertions")
    }
}
