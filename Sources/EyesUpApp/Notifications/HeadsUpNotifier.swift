import EyesUpCore
import Foundation
import UserNotifications

/// Posts "Keep-awake ends at 11:24 PM" before the Mac may sleep, with one-tap extensions.
@MainActor
final class HeadsUpNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let categoryID = "EYESUP_HEADS_UP"

    private enum Action: String {
        case extend30 = "EXTEND_30M"
        case extend60 = "EXTEND_1H"
        case indefinite = "INDEFINITE"
    }

    private let controller: AwakeController
    /// nil when running unbundled (for example `swift run`), where UserNotifications is unavailable.
    private let center: UNUserNotificationCenter?

    init(controller: AwakeController) {
        self.controller = controller
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        guard let center else { return }

        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryID,
                actions: [
                    UNNotificationAction(identifier: Action.extend30.rawValue, title: "+30 min"),
                    UNNotificationAction(identifier: Action.extend60.rawValue, title: "+1 hour"),
                    UNNotificationAction(identifier: Action.indefinite.rawValue, title: "Keep awake ∞"),
                ],
                intentIdentifiers: []
            ),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        controller.setHeadsUpHandler { [weak self] end in self?.post(end: end) }
    }

    private func post(end: Date) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "EyesUpGuardian"
        content.body = "Keep-awake ends at \(end.formatted(date: .omitted, time: .shortened)). Your Mac may sleep after that."
        content.categoryIdentifier = Self.categoryID
        center.add(UNNotificationRequest(identifier: "heads-up", content: content, trigger: nil)) { _ in }
    }

    /// A short informational banner: trigger changes, safety releases, automation results.
    func postInfo(_ body: String, id: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "EyesUpGuardian"
        content.body = body
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { _ in }
    }

    /// Says why when it can't, instead of doing nothing: this runs from a notification button,
    /// where there is no other way to tell the user.
    private func extend(by seconds: TimeInterval) {
        do {
            try controller.extend(by: seconds, policy: controller.currentPolicy)
        } catch let error as AwakeError {
            postInfo(error.message, id: "extend-refused")
        } catch {
            postInfo("That didn't work. Open the dashboard to change this session.", id: "extend-refused")
        }
    }

    private func handle(actionID: String) {
        switch Action(rawValue: actionID) {
        case .extend30: extend(by: 1800)
        case .extend60: extend(by: 3600)
        case .indefinite: controller.startIndefinite(policy: controller.currentPolicy)
        case nil: break
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        await MainActor.run { handle(actionID: actionID) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
