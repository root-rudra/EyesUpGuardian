import Darwin
import Foundation
import IOKit

/// Uptime, load average, how long since you touched the Mac, and thermal state.
public struct SystemProbe {
    public init() {}

    public func sample() -> SystemMetrics? {
        guard let bootTime = Self.bootTime() else { return nil }
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        let thermal: ThermalLevel = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
        return SystemMetrics(
            bootTime: bootTime,
            loadAverage: count == 3 ? (loads[0], loads[1], loads[2]) : (0, 0, 0),
            idleSeconds: Self.idleSeconds() ?? 0,
            thermal: thermal
        )
    }

    private static func bootTime() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }

    /// Seconds since the last keyboard or mouse event, from the HID system's idle counter.
    private static func idleSeconds() -> TimeInterval? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let properties = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return nil }
        return TimeInterval(properties.uint64Value) / 1_000_000_000
    }
}
