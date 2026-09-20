import AppKit
import Carbon.HIToolbox
import Observation

@MainActor
public protocol HotKeyRegistering: AnyObject {
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) -> Bool
    func unregister()
}

/// Carries the handler across the C callback boundary.
private final class HotKeyBox: @unchecked Sendable {
    let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func fire() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.handler() } }
    }
}

/// One shared function pointer: Carbon matches handlers by pointer when removing them.
private let hotKeyCallback: EventHandlerUPP = { _, _, context in
    guard let context else { return noErr }
    Unmanaged<HotKeyBox>.fromOpaque(context).takeUnretainedValue().fire()
    return noErr
}

/// A system-wide shortcut through Carbon, which needs no Accessibility permission — unlike an event
/// tap, which could read every keystroke the user types.
@MainActor
public final class CarbonHotKey: HotKeyRegistering {
    // Opaque Carbon handles: safe to unregister from the deinit below, which is not main-actor isolated.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?
    private var box: HotKeyBox?

    public init() {}

    public func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        let box = HotKeyBox(handler)
        self.box = box

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        guard InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec,
                                  Unmanaged.passUnretained(box).toOpaque(), &handlerRef) == noErr else {
            self.box = nil
            return false
        }
        let id = EventHotKeyID(signature: OSType(0x45_59_45_53), id: 1) // "EYES"
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, hotKeyRef != nil else {
            unregister()
            return false
        }
        return true
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        box = nil
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

@MainActor
@Observable
public final class GlobalShortcut {
    /// ⌃⌥⌘E — E for EyesUp.
    public static let keyCode: UInt32 = 14
    public static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    public static let description = "⌃⌥⌘E"

    public private(set) var isActive = false
    public private(set) var lastError: String?

    @ObservationIgnored private let registrar: any HotKeyRegistering

    public init(registrar: any HotKeyRegistering = CarbonHotKey()) {
        self.registrar = registrar
    }

    public func apply(enabled: Bool, action: @escaping @MainActor () -> Void) {
        guard enabled != isActive else { return }
        guard enabled else {
            registrar.unregister()
            isActive = false
            lastError = nil
            return
        }
        if registrar.register(keyCode: Self.keyCode, modifiers: Self.modifiers, handler: action) {
            isActive = true
            lastError = nil
        } else {
            isActive = false
            lastError = "\(Self.description) is already taken by another app, so the shortcut is off."
        }
    }
}
