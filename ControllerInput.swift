import AppKit
import GameController

/// Deterministic stick filtering; time is monotonic and injectable in tests.
struct AnalogNavigation {
    enum Direction: Equatable { case left, right, up, down }
    static let activation: Float = 0.55
    static let release: Float = 0.30
    static let axisMargin: Float = 0.18
    static let repeatDelay: TimeInterval = 0.45
    static let repeatInterval: TimeInterval = 0.14

    private var context: String?
    private var needsNeutral = true
    private var direction: Direction?
    private var nextRepeat: TimeInterval?

    mutating func suspend() {
        needsNeutral = true
        direction = nil
        nextRepeat = nil
    }

    mutating func sample(x: Float, y: Float, time: TimeInterval,
                         context newContext: String?, repeats: Bool) -> Direction? {
        if context != newContext {
            context = newContext
            suspend()
        }
        guard newContext != nil, x.isFinite, y.isFinite, time.isFinite else {
            suspend()
            return nil
        }
        let horizontal = abs(x), vertical = abs(y)
        if max(horizontal, vertical) <= Self.release {
            needsNeutral = false
            direction = nil
            nextRepeat = nil
            return nil
        }
        guard !needsNeutral else { return nil }

        // Keep the current axis around diagonals instead of oscillating between
        // a one-card move and a whole row. Only one direction is emitted at once.
        let retained: Bool
        switch direction {
        case .left: retained = -x > Self.release && vertical < horizontal + Self.axisMargin
        case .right: retained = x > Self.release && vertical < horizontal + Self.axisMargin
        case .up: retained = y > Self.release && horizontal < vertical + Self.axisMargin
        case .down: retained = -y > Self.release && horizontal < vertical + Self.axisMargin
        case nil: retained = false
        }
        let candidate: Direction?
        if retained { candidate = direction }
        else if max(horizontal, vertical) >= Self.activation {
            candidate = horizontal >= vertical ? (x < 0 ? .left : .right) : (y > 0 ? .up : .down)
        } else { candidate = nil }

        guard let candidate else {
            direction = nil
            nextRepeat = nil
            return nil
        }
        if candidate != direction {
            direction = candidate
            nextRepeat = repeats ? time + Self.repeatDelay : nil
            return candidate
        }
        guard repeats else { nextRepeat = nil; return nil }
        guard let deadline = nextRepeat else {
            nextRepeat = time + Self.repeatDelay
            return nil
        }
        guard time >= deadline else { return nil }
        // A delayed UI frame must not cause a burst of catch-up movements.
        nextRepeat = time + Self.repeatInterval
        return candidate
    }
}

/// Reads the first supported connected controller while the launcher is active.
@MainActor
final class ControllerInput {
    private let onMove: (Int) -> Void
    private let onVerticalMove: ((Int) -> Void)?
    private let onConfirm: () -> Void
    private let onBack: () -> Void
    private let onFullscreen: () -> Void
    private let onCatalog: () -> Void
    private let onConnectionChanged: (String?) -> Void
    private let navigationContext: () -> String?
    private let repeatsAnalog: () -> Bool

    private var observers: [NSObjectProtocol] = []
    private var controller: GCController?
    private var heldInputs: Set<String> = []
    private var started = false
    private var generation = 0
    private var analog = AnalogNavigation()
    private var analogTimer: Timer?

    init(
        onMove: @escaping (Int) -> Void,
        onVerticalMove: ((Int) -> Void)? = nil,
        onConfirm: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onFullscreen: @escaping () -> Void = {},
        onCatalog: @escaping () -> Void = {},
        navigationContext: @escaping () -> String? = { "launcher" },
        repeatsAnalog: @escaping () -> Bool = { false },
        onConnectionChanged: @escaping (String?) -> Void
    ) {
        self.onMove = onMove
        self.onVerticalMove = onVerticalMove
        self.onConfirm = onConfirm
        self.onBack = onBack
        self.onFullscreen = onFullscreen
        self.onCatalog = onCatalog
        self.onConnectionChanged = onConnectionChanged
        self.navigationContext = navigationContext
        self.repeatsAnalog = repeatsAnalog
    }

    func start() {
        guard !started else { return }
        started = true
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshController() }
            })
        }
        refreshController()
    }

    func stop() {
        guard started else { return }
        started = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        detachController()
        onConnectionChanged(nil)
    }

    private func refreshController() {
        guard started else { return }
        let available = GCController.controllers().filter { $0.extendedGamepad != nil }
        if let controller, available.contains(where: { $0 === controller }) {
            return
        }

        detachController()
        guard let next = available.first, let pad = next.extendedGamepad else {
            onConnectionChanged(nil)
            return
        }

        controller = next
        next.handlerQueue = .main
        bind(pad.dpad.up, name: "up") { ($0.onVerticalMove ?? $0.onMove)(-1) }
        bind(pad.dpad.left, name: "left") { $0.onMove(-1) }
        bind(pad.dpad.down, name: "down") { ($0.onVerticalMove ?? $0.onMove)(1) }
        bind(pad.dpad.right, name: "right") { $0.onMove(1) }
        // GameController uses the physical south/east positions: Cross/Circle on DualSense.
        bind(pad.buttonA, name: "confirm") { $0.onConfirm() }
        bind(pad.buttonB, name: "back") { $0.onBack() }
        bind(pad.buttonX, name: "fullscreen") { $0.onFullscreen() }
        // North face button: Triangle on DualSense.
        bind(pad.buttonY, name: "catalog") { $0.onCatalog() }
        let bindingGeneration = generation
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, _, _ in
            Task { @MainActor in
                guard let self, self.started, self.generation == bindingGeneration else { return }
                self.refreshAnalogNavigation()
            }
        }
        // A controller connected with the stick held must return to neutral.
        refreshAnalogNavigation()
        onConnectionChanged(next.vendorName ?? "Controle conectado")
    }

    private func bind(
        _ button: GCControllerButtonInput,
        name: String,
        action: @escaping @MainActor (ControllerInput) -> Void
    ) {
        if button.isPressed { heldInputs.insert(name) }
        let bindingGeneration = generation
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                guard let self, self.started, self.generation == bindingGeneration else { return }
                if !pressed {
                    self.heldInputs.remove(name)
                    return
                }
                guard self.heldInputs.insert(name).inserted, NSApp.isActive else { return }
                // A held stick must not carry movement through X/O/Triangle or
                // compete with a deliberate D-pad press.
                self.suspendAnalogNavigation()
                action(self)
                self.refreshAnalogNavigation()
            }
        }
    }

    func suspendAnalogNavigation() {
        analog.suspend()
        analogTimer?.invalidate()
        analogTimer = nil
    }

    /// Also called on focus/window changes; never reads the games or SSD.
    func refreshAnalogNavigation() {
        guard started, let stick = controller?.extendedGamepad?.leftThumbstick else { return }
        let context = NSApp.isActive ? navigationContext() : nil
        let x = stick.xAxis.value, y = stick.yAxis.value
        let movement = analog.sample(x: x, y: y, time: ProcessInfo.processInfo.systemUptime,
                                     context: context, repeats: repeatsAnalog())
        switch movement {
        case .left: onMove(-1)
        case .right: onMove(1)
        case .up: (onVerticalMove ?? onMove)(-1)
        case .down: (onVerticalMove ?? onMove)(1)
        case nil: break
        }
        guard context != nil, x.isFinite, y.isFinite,
              max(abs(x), abs(y)) > AnalogNavigation.release else {
            analogTimer?.invalidate()
            analogTimer = nil
            return
        }
        // Poll only while tilted, so steady holds repeat even without new
        // GameController value events. Neutral/background input has no timer.
        guard analogTimer == nil else { return }
        let bindingGeneration = generation
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.started, self.generation == bindingGeneration else { return }
                self.refreshAnalogNavigation()
            }
        }
        timer.tolerance = 0.008
        analogTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func detachController() {
        generation += 1
        suspendAnalogNavigation()
        analog = AnalogNavigation()
        if let pad = controller?.extendedGamepad {
            pad.leftThumbstick.valueChangedHandler = nil
            for button in [pad.dpad.up, pad.dpad.left, pad.dpad.down, pad.dpad.right,
                           pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY] {
                button.pressedChangedHandler = nil
            }
        }
        controller = nil
        heldInputs.removeAll()
    }
}
