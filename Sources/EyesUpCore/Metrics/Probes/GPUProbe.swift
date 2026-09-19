import Foundation
import IOKit

/// GPU utilization from the accelerator's published statistics — a registry read, not a private API.
public struct GPUProbe {
    public init() {}

    public func sample() -> GPUMetrics? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                let utilization = statistics["Device Utilization %"] as? NSNumber else { continue }
            let value = utilization.doubleValue
            guard value.isFinite else { return nil }
            return GPUMetrics(utilization: min(max(value, 0), 100))
        }
        return nil
    }
}
