import Darwin
import Foundation

/// Memory as Activity Monitor reports it: used, app, wired, compressed, plus pressure and swap.
public struct MemoryProbe {
    public init() {}

    public func sample() -> MemoryMetrics? {
        var statistics = vm_statistics64()
        // mach_host_self() hands out a new send right each call; it has to be given back.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // sysconf is a function call, so it avoids Swift 6's ban on reading mutable C globals.
        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let wired = UInt64(statistics.wire_count) * pageSize
        let compressed = UInt64(statistics.compressor_page_count) * pageSize
        let active = UInt64(statistics.active_count) * pageSize
        let speculative = UInt64(statistics.speculative_count) * pageSize
        let purgeable = UInt64(statistics.purgeable_count) * pageSize
        let external = UInt64(statistics.external_page_count) * pageSize
        // Activity Monitor's "App Memory": anonymous pages that aren't file-backed or purgeable.
        let app = active + speculative > purgeable + external ? active + speculative - purgeable - external : 0
        let used = app + wired + compressed

        return MemoryMetrics(
            usedBytes: min(used, ProcessInfo.processInfo.physicalMemory),
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            swapUsedBytes: Self.swapUsed(),
            pressure: Self.pressure()
        )
    }

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
