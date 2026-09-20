import Foundation
import Testing
@testable import EyesUpApp

@Suite @MainActor struct HotKeyTests {
    @MainActor
    final class FakeRegistrar: HotKeyRegistering {
        var succeeds = true
        private(set) var registrations = 0
        private(set) var unregistrations = 0
        private var handler: (@MainActor () -> Void)?

        func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) -> Bool {
            registrations += 1
            guard succeeds else { return false }
            self.handler = handler
            return true
        }

        func unregister() {
            unregistrations += 1
            handler = nil
        }

        func press() { handler?() }
    }

    @Test func enablingRegistersAndPressingFires() {
        let registrar = FakeRegistrar()
        let shortcut = GlobalShortcut(registrar: registrar)
        var fired = 0
        shortcut.apply(enabled: true) { fired += 1 }
        #expect(shortcut.isActive)
        registrar.press()
        #expect(fired == 1)
    }

    @Test func disablingTheShortcutUnregistersIt() {
        let registrar = FakeRegistrar()
        let shortcut = GlobalShortcut(registrar: registrar)
        shortcut.apply(enabled: true) {}
        shortcut.apply(enabled: false) {}
        #expect(!shortcut.isActive)
        #expect(registrar.unregistrations == 1)
    }

    @Test func aRefusedHotKeyIsReported() {
        // Another app already owns this combination.
        let registrar = FakeRegistrar()
        registrar.succeeds = false
        let shortcut = GlobalShortcut(registrar: registrar)
        shortcut.apply(enabled: true) {}
        #expect(!shortcut.isActive)
        #expect(shortcut.lastError != nil)
    }

    @Test func applyingTwiceDoesNotStackRegistrations() {
        let registrar = FakeRegistrar()
        let shortcut = GlobalShortcut(registrar: registrar)
        shortcut.apply(enabled: true) {}
        shortcut.apply(enabled: true) {}
        #expect(registrar.registrations == 1)
    }
}
