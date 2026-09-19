import Foundation

/// Everything the center can read. A probe that can't read its source leaves that slot nil.
public protocol MetricsProbing: Sendable {
    func sample(_ ids: Set<MetricID>) -> MetricsSnapshot
    /// Counters jumped (the Mac slept): drop rate baselines instead of reporting a fake burst.
    func resetBaselines()
}

/// Where sampling runs. Production uses a background queue; tests run inline and deterministically.
public protocol MetricsExecuting: Sendable {
    func run(_ work: @escaping @Sendable () -> MetricsSnapshot, completion: @escaping @MainActor (MetricsSnapshot) -> Void)
}

public struct InlineExecutor: MetricsExecuting {
    public init() {}

    public func run(_ work: @escaping @Sendable () -> MetricsSnapshot, completion: @escaping @MainActor (MetricsSnapshot) -> Void) {
        let snapshot = work()
        MainActor.assumeIsolated { completion(snapshot) }
    }
}

/// One serial queue for every sample, so probing never blocks the UI (spec §2 data flow).
public struct BackgroundExecutor: MetricsExecuting {
    private let queue = DispatchQueue(label: "dev.eyesupguardian.metrics", qos: .utility)

    public init() {}

    public func run(_ work: @escaping @Sendable () -> MetricsSnapshot, completion: @escaping @MainActor (MetricsSnapshot) -> Void) {
        queue.async {
            let snapshot = work()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(snapshot) } }
        }
    }
}
