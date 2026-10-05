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

/// Fires once when L2 and R2 are both down. Releasing only one trigger does
/// not arm another reload; both must return to rest first.
struct TriggerChord {
    private var left = false
    private var right = false
    private var armed = true

    mutating func adopt(left: Bool, right: Bool) {
        self.left = left
        self.right = right
        armed = !(left && right)
    }

    @discardableResult
    mutating func update(left nextLeft: Bool?, right nextRight: Bool?) -> Bool {
        if let nextLeft { left = nextLeft }
        if let nextRight { right = nextRight }
        if left && right {
            guard armed else { return false }
            armed = false
            return true
        }
        if !left && !right { armed = true }
        return false
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
    private let onReload: () -> Void
    private let onSort: (Bool) -> Void
    private let onFolders: () -> Void
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
    private var triggerChord = TriggerChord()

    init(
        onMove: @escaping (Int) -> Void,
        onVerticalMove: ((Int) -> Void)? = nil,
        onConfirm: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onFullscreen: @escaping () -> Void = {},
        onCatalog: @escaping () -> Void = {},
        onReload: @escaping () -> Void = {},
        onSort: @escaping (Bool) -> Void = { _ in },
        onFolders: @escaping () -> Void = {},
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
        self.onReload = onReload
        self.onSort = onSort
        self.onFolders = onFolders
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
        // GameController uses the physical south/east positions: Cross/Circle on DualSense.
        bind(pad.buttonA, name: "confirm") { $0.onConfirm() }
        bind(pad.buttonB, name: "back") { $0.onBack() }
        bind(pad.buttonX, name: "fullscreen") { $0.onFullscreen() }
        // North face button: Triangle on DualSense.
        bind(pad.buttonY, name: "catalog") { $0.onCatalog() }
        bind(pad.leftShoulder, name: "sort-az") { $0.onSort(true) }
        bind(pad.rightShoulder, name: "sort-za") { $0.onSort(false) }
        if let options = pad.buttonOptions {
            bind(options, name: "folders") { $0.onFolders() }
        }
        triggerChord.adopt(left: pad.leftTrigger.isPressed, right: pad.rightTrigger.isPressed)
        bindTrigger(pad.leftTrigger, isLeft: true)
        bindTrigger(pad.rightTrigger, isLeft: false)
        let bindingGeneration = generation
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, _, _ in
            Task { @MainActor in
                guard let self, self.started, self.generation == bindingGeneration else { return }
                self.refreshAnalogNavigation()
            }
        }
        pad.dpad.valueChangedHandler = { [weak self] _, _, _ in
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
        allowsBackground: Bool = false,
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
                guard self.heldInputs.insert(name).inserted else { return }
                if !allowsBackground, !NSApp.isActive { return }
                // A held stick must not carry movement through X/O/Triangle or
                // compete with a deliberate D-pad press.
                self.suspendAnalogNavigation()
                action(self)
                self.refreshAnalogNavigation()
            }
        }
    }

    private func bindTrigger(_ button: GCControllerButtonInput, isLeft: Bool) {
        let bindingGeneration = generation
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                guard let self, self.started, self.generation == bindingGeneration else { return }
                let fired = self.triggerChord.update(left: isLeft ? pressed : nil, right: isLeft ? nil : pressed)
                guard fired, NSApp.isActive else { return }
                self.suspendAnalogNavigation()
                self.onReload()
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
        guard started, let pad = controller?.extendedGamepad else { return }
        let stick = pad.leftThumbstick
        let context = NSApp.isActive ? navigationContext() : nil
        let dpadActive = abs(pad.dpad.xAxis.value) > 0.5 || abs(pad.dpad.yAxis.value) > 0.5
        let x = dpadActive ? pad.dpad.xAxis.value : stick.xAxis.value
        let y = dpadActive ? pad.dpad.yAxis.value : stick.yAxis.value
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
            pad.dpad.valueChangedHandler = nil
            for button in [pad.dpad.up, pad.dpad.left, pad.dpad.down, pad.dpad.right,
                           pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY,
                           pad.leftShoulder, pad.rightShoulder] {
                button.pressedChangedHandler = nil
            }
            pad.buttonOptions?.pressedChangedHandler = nil
            pad.leftTrigger.pressedChangedHandler = nil
            pad.rightTrigger.pressedChangedHandler = nil
        }
        triggerChord = TriggerChord()
        controller = nil
        heldInputs.removeAll()
    }
}
