import Foundation
import Testing
@testable import EyesUpApp
@testable import EyesUpCore

@Suite @MainActor struct LaunchAtLoginTests {
    final class FakeLoginService: LoginItemService, @unchecked Sendable {
        var registered = false
        var failure: (any Error)?
        private(set) var registerCalls = 0
        private(set) var unregisterCalls = 0

        var isRegistered: Bool { registered }

        func register() throws {
            registerCalls += 1
            if let failure { throw failure }
            registered = true
        }

        func unregister() throws {
            unregisterCalls += 1
            if let failure { throw failure }
            registered = false
        }
    }

    struct Refused: Error {}

    @Test func toggleReflectsWhatTheSystemReports() {
        let service = FakeLoginService()
        let login = LaunchAtLogin(service: service)
        #expect(!login.isEnabled)

        #expect(login.set(true) == nil)
        #expect(login.isEnabled)
        #expect(service.registerCalls == 1)

        #expect(login.set(false) == nil)
        #expect(!login.isEnabled)
        #expect(service.unregisterCalls == 1)
    }

    @Test func aRefusedRegistrationIsReported() {
        let service = FakeLoginService()
        service.failure = Refused()
        let login = LaunchAtLogin(service: service)
        let message = login.set(true)
        #expect(message != nil)
        #expect(!login.isEnabled) // never claims success it didn't get
    }

    @Test func theSystemIsTheSourceOfTruth() {
        // The user can turn it off in System Settings; the app must follow, not insist.
        let service = FakeLoginService()
        let login = LaunchAtLogin(service: service)
        _ = login.set(true)
        service.registered = false
        #expect(!login.syncFromSystem())
        #expect(!login.isEnabled)
    }
}
