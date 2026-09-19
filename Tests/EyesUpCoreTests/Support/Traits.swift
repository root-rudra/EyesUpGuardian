import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// Tests that touch real macOS power management. Run with `make test-integration`.
    static var integration: Self {
        .enabled(if: ProcessInfo.processInfo.environment["EYESUP_INTEGRATION"] == "1", "set EYESUP_INTEGRATION=1")
    }
}
