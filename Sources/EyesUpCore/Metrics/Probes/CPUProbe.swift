import Darwin
import Foundation

/// Per-core busy percentages from Mach tick counters. The first sample only sets a baseline.
public final class CPUProbe {
    private var previous: [(busy: UInt64, total: UInt64)] = []
    private let efficiencyCoreCount: Int

    public init() {
        efficiencyCoreCount = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    }

    public func sample() -> CPUMetrics? {
        guard let current = Self.coreTicks() else { return nil }
        defer { previous = current }
        guard previous.count == current.count, !current.isEmpty else { return nil }

        var cores: [Double] = []
        var busyDelta: UInt64 = 0
        var totalDelta: UInt64 = 0
        for (index, ticks) in current.enumerated() {
            let last = previous[index]
            guard ticks.total > last.total, ticks.busy >= last.busy else { return nil } // counters reset
            let busy = ticks.busy - last.busy
            let total = ticks.total - last.total
            busyDelta += busy
            totalDelta += total
            cores.append(Double(busy) / Double(total) * 100)
        }
        guard totalDelta > 0 else { return nil }

        // Apple Silicon numbers efficiency cores first.
        let efficiency = efficiencyCoreCount > 0 && efficiencyCoreCount <= cores.count
            ? cores.prefix(efficiencyCoreCount).reduce(0, +) / Double(efficiencyCoreCount)
            : nil
        let performanceCores = efficiencyCoreCount < cores.count ? Array(cores.dropFirst(efficiencyCoreCount)) : []
        let performance = performanceCores.isEmpty ? nil : performanceCores.reduce(0, +) / Double(performanceCores.count)

        return CPUMetrics(
            total: Double(busyDelta) / Double(totalDelta) * 100,
            cores: cores,
            performance: performance,
            efficiency: efficiency
        )
    }

    /// Tick counters are unsigned 32-bit, but Mach hands them over as Int32: past ~250 days of uptime
    /// they read negative, and converting straight to UInt64 would trap and kill the app.
    static func unsignedTick(_ raw: Int32) -> UInt64 {
        UInt64(UInt32(bitPattern: raw))
    }

    private static func coreTicks() -> [(busy: UInt64, total: UInt64)]? {
        // mach_host_self() hands out a new send right each call; it has to be given back.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        // The kernel reports both the processor count and how many integers it wrote; only index
        // inside what it actually wrote.
        guard Int(count) * Int(CPU_STATE_MAX) <= Int(infoCount) else { return nil }
        var ticks: [(busy: UInt64, total: UInt64)] = []
        ticks.reserveCapacity(Int(count))
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            let user = unsignedTick(info[base + Int(CPU_STATE_USER)])
            let system = unsignedTick(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = unsignedTick(info[base + Int(CPU_STATE_IDLE)])
            let nice = unsignedTick(info[base + Int(CPU_STATE_NICE)])
            ticks.append((busy: user + system + nice, total: user + system + nice + idle))
        }
        return ticks
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
