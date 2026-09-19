import Foundation
import Testing
@testable import EyesUpApp

@Suite @MainActor struct PopoverFormStateTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func openingUntilResetsTheDateToAnHourFromNow() {
        let form = PopoverFormState()
        form.untilDate = Date(timeIntervalSince1970: 0) // e.g. set when the app launched days ago
        form.select(.until, now: now)
        #expect(form.entry == .until)
        #expect(form.untilDate == now.addingTimeInterval(3600))
    }

    @Test func selectingTheOpenPanelAgainClosesIt() {
        let form = PopoverFormState()
        form.select(.custom, now: now)
        form.select(.custom, now: now)
        #expect(form.entry == .none)
    }

    @Test func selectingAPanelClearsTheError() {
        let form = PopoverFormState()
        form.errorMessage = "old error"
        form.select(.pid, now: now)
        #expect(form.errorMessage == nil)
    }
}
