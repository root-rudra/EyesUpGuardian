import Foundation
import ServiceManagement

/// Registering the app itself to open at login. Behind a protocol so tests never touch the real
/// login-item database.
public protocol LoginItemService: Sendable {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

/// `SMAppService.mainApp` opens *this app* at login. It installs no daemon and no agent, needs no
/// admin rights, and the user can override it in System Settings — which is why the system, not this
/// app, is the source of truth.
public struct SystemLoginItem: LoginItemService {
    public init() {}

    public var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
@Observable
public final class LaunchAtLogin {
    public private(set) var isEnabled: Bool

    @ObservationIgnored private let service: any LoginItemService

    public init(service: any LoginItemService = SystemLoginItem()) {
        self.service = service
        isEnabled = service.isRegistered
    }

    /// Returns nil on success, or a message to show when macOS refuses.
    @discardableResult
    public func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            isEnabled = service.isRegistered
            return isEnabled == enabled ? nil : "macOS didn't apply that. Check Login Items in System Settings."
        } catch {
            isEnabled = service.isRegistered
            return "macOS refused: \(error.localizedDescription). An app built from source has to be in /Applications for this to work."
        }
    }

    /// The user may have changed it in System Settings; believe the system.
    @discardableResult
    public func syncFromSystem() -> Bool {
        isEnabled = service.isRegistered
        return isEnabled
    }
}
