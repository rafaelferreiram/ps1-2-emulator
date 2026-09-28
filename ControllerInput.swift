import AppKit
import GameController

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

    private var observers: [NSObjectProtocol] = []
    private var controller: GCController?
    private var heldInputs: Set<String> = []
    private var started = false
    private var generation = 0

    init(
        onMove: @escaping (Int) -> Void,
        onVerticalMove: ((Int) -> Void)? = nil,
        onConfirm: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onFullscreen: @escaping () -> Void = {},
        onCatalog: @escaping () -> Void = {},
        onConnectionChanged: @escaping (String?) -> Void
    ) {
        self.onMove = onMove
        self.onVerticalMove = onVerticalMove
        self.onConfirm = onConfirm
        self.onBack = onBack
        self.onFullscreen = onFullscreen
        self.onCatalog = onCatalog
        self.onConnectionChanged = onConnectionChanged
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
                action(self)
            }
        }
    }

    private func detachController() {
        generation += 1
        if let pad = controller?.extendedGamepad {
            for button in [pad.dpad.up, pad.dpad.left, pad.dpad.down, pad.dpad.right,
                           pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY] {
                button.pressedChangedHandler = nil
            }
        }
        controller = nil
        heldInputs.removeAll()
    }
}
