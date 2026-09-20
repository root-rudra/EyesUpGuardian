import Foundation

/// One reading the app can sample. UI surfaces subscribe by these.
public enum MetricID: String, CaseIterable, Sendable {
    case cpu, memory, system, storage, network, processes, power, fans, temperature, gpu, otherAssertions
}

public struct CPUMetrics: Equatable, Sendable {
    public var total: Double
    public var cores: [Double]
    /// Averages per cluster; nil when the split can't be read.
    public var performance: Double?
    public var efficiency: Double?

    public init(total: Double, cores: [Double], performance: Double?, efficiency: Double?) {
        self.total = total
        self.cores = cores
        self.performance = performance
        self.efficiency = efficiency
    }
}

public enum MemoryPressure: String, Equatable, Sendable {
    case normal, warning, critical
}

public struct MemoryMetrics: Equatable, Sendable {
    public var usedBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var totalBytes: UInt64
    public var swapUsedBytes: UInt64
    public var pressure: MemoryPressure

    public init(usedBytes: UInt64, appBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64,
                totalBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.totalBytes = totalBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }
}

public struct SystemMetrics: Equatable, Sendable {
    public var bootTime: Date
    public var loadAverage: (Double, Double, Double)
    public var idleSeconds: TimeInterval
    public var thermal: ThermalLevel

    public init(bootTime: Date, loadAverage: (Double, Double, Double), idleSeconds: TimeInterval, thermal: ThermalLevel) {
        self.bootTime = bootTime
        self.loadAverage = loadAverage
        self.idleSeconds = idleSeconds
        self.thermal = thermal
    }

    public static func == (lhs: SystemMetrics, rhs: SystemMetrics) -> Bool {
        lhs.bootTime == rhs.bootTime && lhs.loadAverage == rhs.loadAverage
            && lhs.idleSeconds == rhs.idleSeconds && lhs.thermal == rhs.thermal
    }
}

public struct StorageMetrics: Equatable, Sendable {
    public var freeBytes: UInt64
    public var totalBytes: UInt64
    /// nil until a second sample gives a rate.
    public var readBytesPerSecond: Double?
    public var writeBytesPerSecond: Double?

    public init(freeBytes: UInt64, totalBytes: UInt64, readBytesPerSecond: Double?, writeBytesPerSecond: Double?) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }
}

public struct NetworkMetrics: Equatable, Sendable {
    public var inBytesPerSecond: Double?
    public var outBytesPerSecond: Double?

    public init(inBytesPerSecond: Double?, outBytesPerSecond: Double?) {
        self.inBytesPerSecond = inBytesPerSecond
        self.outBytesPerSecond = outBytesPerSecond
    }
}

public struct ProcessEntry: Identifiable, Equatable, Sendable {
    public var id: Int32 { pid }
    public var pid: Int32
    /// PID *and* start time, captured when this row was sampled. Acting on a row later must use this,
    /// or a PID recycled in the meantime would be treated as the process the user chose.
    public var identity: ProcessIdentity
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var threads: Int
    public var isOwn: Bool
    /// macOS itself, or something installed on this Mac. Read once per process, not per sample.
    public var origin: ProcessOrigin
    /// The executable's path, when it is readable. Used for the row's icon and Reveal in Finder.
    public var executablePath: String?

    public init(pid: Int32, identity: ProcessIdentity, name: String, cpuPercent: Double,
                memoryBytes: UInt64, threads: Int, isOwn: Bool,
                origin: ProcessOrigin = .unknown, executablePath: String? = nil) {
        self.pid = pid
        self.identity = identity
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.threads = threads
        self.isOwn = isOwn
        self.origin = origin
        self.executablePath = executablePath
    }
}

public struct PowerMetrics: Equatable, Sendable {
    public var watts: Double
    public init(watts: Double) { self.watts = watts }
}

public struct FanReading: Equatable, Sendable {
    public var index: Int
    public var rpm: Double
    public var maxRPM: Double?

    public init(index: Int, rpm: Double, maxRPM: Double?) {
        self.index = index
        self.rpm = rpm
        self.maxRPM = maxRPM
    }
}

public struct FanMetrics: Equatable, Sendable {
    public var fans: [FanReading]
    public init(fans: [FanReading]) { self.fans = fans }
}

public struct TemperatureMetrics: Equatable, Sendable {
    /// The hottest curated sensor: Apple publishes no sensor map, so naming one would be guesswork.
    public var celsius: Double
    public var sensorCount: Int

    public init(celsius: Double, sensorCount: Int) {
        self.celsius = celsius
        self.sensorCount = sensorCount
    }
}

public struct GPUMetrics: Equatable, Sendable {
    public var utilization: Double
    public init(utilization: Double) { self.utilization = utilization }
}

/// Another app holding a sleep assertion (spec §6.2).
public struct OtherAssertion: Hashable, Sendable {
    public var processName: String
    public var type: String

    public init(processName: String, type: String) {
        self.processName = processName
        self.type = type
    }
}

/// Everything the app knows right now. A nil slot means "not sampled" or "not available on this Mac".
public struct MetricsSnapshot: Equatable, Sendable {
    public var cpu: CPUMetrics?
    public var memory: MemoryMetrics?
    public var system: SystemMetrics?
    public var storage: StorageMetrics?
    public var network: NetworkMetrics?
    public var processes: [ProcessEntry]?
    public var power: PowerMetrics?
    public var fans: FanMetrics?
    public var temperature: TemperatureMetrics?
    public var gpu: GPUMetrics?
    public var otherAssertions: [OtherAssertion]?

    public init() {}

    public var availableIDs: Set<MetricID> {
        var ids: Set<MetricID> = []
        if cpu != nil { ids.insert(.cpu) }
        if memory != nil { ids.insert(.memory) }
        if system != nil { ids.insert(.system) }
        if storage != nil { ids.insert(.storage) }
        if network != nil { ids.insert(.network) }
        if processes != nil { ids.insert(.processes) }
        if power != nil { ids.insert(.power) }
        if fans != nil { ids.insert(.fans) }
        if temperature != nil { ids.insert(.temperature) }
        if gpu != nil { ids.insert(.gpu) }
        if otherAssertions != nil { ids.insert(.otherAssertions) }
        return ids
    }

    /// `other` wins wherever it has a reading; everything else is kept, so an unsubscribed
    /// metric doesn't blank out while a different surface is open.
    public func merging(_ other: MetricsSnapshot) -> MetricsSnapshot {
        var merged = self
        if let value = other.cpu { merged.cpu = value }
        if let value = other.memory { merged.memory = value }
        if let value = other.system { merged.system = value }
        if let value = other.storage { merged.storage = value }
        if let value = other.network { merged.network = value }
        if let value = other.processes { merged.processes = value }
        if let value = other.power { merged.power = value }
        if let value = other.fans { merged.fans = value }
        if let value = other.temperature { merged.temperature = value }
        if let value = other.gpu { merged.gpu = value }
        if let value = other.otherAssertions { merged.otherAssertions = value }
        return merged
    }
}
