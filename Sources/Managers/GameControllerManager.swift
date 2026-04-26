import Foundation
import GameController

/// MFi / Xbox / DualShock / DualSense / Joy-Con (iOS 16+) desteği.
/// Fiziksel controller bağlandığında `onAction` callback'i üzerinden
/// CoreBridge'e aynı GamepadAction tipini yollar.
final class GameControllerManager {
    static let shared = GameControllerManager()
    private init() {}

    var onAction: ((GamepadAction) -> Void)?
    private(set) var isConnected: Bool = false
    private var controller: GCController?

    // MARK: Lifecycle

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didConnect(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didDisconnect(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )

        GCController.startWirelessControllerDiscovery {}

        if let existing = GCController.controllers().first {
            bind(controller: existing)
        }
    }

    func stop() {
        GCController.stopWirelessControllerDiscovery()
        NotificationCenter.default.removeObserver(self)
        controller = nil
        isConnected = false
    }

    // MARK: Connection

    @objc private func didConnect(_ note: Notification) {
        guard let gc = note.object as? GCController else { return }
        bind(controller: gc)
    }

    @objc private func didDisconnect(_ note: Notification) {
        controller = nil
        isConnected = false
    }

    // MARK: Binding

    private func bind(controller gc: GCController) {
        self.controller = gc
        self.isConnected = true

        guard let pad = gc.extendedGamepad else { return }

        // Face buttons — PlayStation terminolojisine map
        pad.buttonA.pressedChangedHandler      = { [weak self] _, _, p in self?.onAction?(.cross(p)) }
        pad.buttonB.pressedChangedHandler      = { [weak self] _, _, p in self?.onAction?(.circle(p)) }
        pad.buttonX.pressedChangedHandler      = { [weak self] _, _, p in self?.onAction?(.square(p)) }
        pad.buttonY.pressedChangedHandler      = { [weak self] _, _, p in self?.onAction?(.triangle(p)) }

        // Shoulders & triggers
        pad.leftShoulder.pressedChangedHandler  = { [weak self] _, _, p in self?.onAction?(.l1(p)) }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, p in self?.onAction?(.r1(p)) }
        pad.leftTrigger.pressedChangedHandler   = { [weak self] _, _, p in self?.onAction?(.l2(p)) }
        pad.rightTrigger.pressedChangedHandler  = { [weak self] _, _, p in self?.onAction?(.r2(p)) }

        // D-Pad
        pad.dpad.up.pressedChangedHandler    = { [weak self] _, _, p in self?.onAction?(.dpadUp(p)) }
        pad.dpad.down.pressedChangedHandler  = { [weak self] _, _, p in self?.onAction?(.dpadDown(p)) }
        pad.dpad.left.pressedChangedHandler  = { [weak self] _, _, p in self?.onAction?(.dpadLeft(p)) }
        pad.dpad.right.pressedChangedHandler = { [weak self] _, _, p in self?.onAction?(.dpadRight(p)) }

        // Start / Select (iOS 13+ menu/options buttons)
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, p in self?.onAction?(.start(p)) }
        pad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, p in self?.onAction?(.select(p)) }

        // Analog sticks — continuous callback
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.onAction?(.leftStick(x: x, y: -y))   // Y ekseni invert
        }
        pad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.onAction?(.rightStick(x: x, y: -y))
        }

        print("[GameController] Bound: \(gc.vendorName ?? "Unknown")")
    }

    // MARK: Haptics (DualSense / DualShock 4)
    // Gelişmiş CHHapticEngine pattern'ları için GCHapticsLocality.default kullan —
    // şimdilik stub olarak kaldı, ileride CoreHaptics ile zenginleştirilebilir.
    func rumble(intensity: Float = 0.6, duration: TimeInterval = 0.1) {
        // TODO: CHHapticEngine pattern yaz
    }
}
