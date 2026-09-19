import Foundation
@testable import EyesUpCore

let referenceDate = Date(timeIntervalSince1970: 1_000_000)

func makeHold(
    label: String = "Test hold",
    policy: SleepPolicy = .system,
    end: HoldEnd = .indefinite,
    grace: TimeInterval? = nil,
    source: HoldSource = .manual,
    createdAt: Date = referenceDate
) -> Hold {
    Hold(source: source, label: label, policy: policy, end: end, grace: grace, createdAt: createdAt)
}
