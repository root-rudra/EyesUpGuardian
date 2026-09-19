import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Carries a main-actor handler across a C callback boundary.
private final class CallbackBox: @unchecked Sendable {
    let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func fire() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.handler() } }
    }
}

// One shared function pointer per API: CoreGraphics only removes a callback that is
// *identical* to the one registered, and two identical closures are two different pointers.
private let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, context in
    guard !flags.contains(.beginConfigurationFlag), let context else { return }
    Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().fire()
}

private let powerCallback: IOPowerSourceCallbackType = { context in
    guard let context else { return }
    Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().fire()
}

/// Kernel counters for the activity triggers. Everything here works without admin rights.
public struct LiveSystemCounters: SystemCounters {
    public init() {}

    public func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        let user = UInt64(ticks.0), system = UInt64(ticks.1), idle = UInt64(ticks.2), nice = UInt64(ticks.3)
        return (busy: user + system + nice, total: user + system + idle + nice)
    }

    /// Bytes in + out across every non-loopback interface, from the 64-bit interface list.
    public func networkBytes() -> UInt64? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }

        var total: UInt64 = 0
        var offset = 0
        buffer.withUnsafeBytes { raw in
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2 {
                    let extended = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if extended.ifm_data.ifi_type != UInt8(IFT_LOOP) {
                        total += extended.ifm_data.ifi_ibytes + extended.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return total
    }

    public func diskBytesWritten() -> UInt64? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var total: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                let written = statistics["Bytes (Write)"] as? NSNumber else { continue }
            total += written.uint64Value
        }
        return total
    }
}

/// Process names visible to this user (libproc).
public struct LiveProcessLister: ProcessLister {
    public init() {}

    public func runningProcessNames() -> Set<String> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let written = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard written > 0 else { return [] }

        var names: Set<String> = []
        for pid in pids.prefix(Int(written)) where pid > 0 {
            var buffer = [CChar](repeating: 0, count: 256)
            let length = proc_name(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { continue }
            names.insert(String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        return names
    }
}

@MainActor
public final class LiveDisplayInventory: DisplayInventory {
    private var box: CallbackBox?

    public init() {}

    public func connectedDisplays() -> [DisplayMatch] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { id in
            DisplayMatch(
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id),
                name: "Display \(CGDisplayModelNumber(id))"
            )
        }
    }

    public func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let box = CallbackBox(handler)
        self.box = box
        CGDisplayRegisterReconfigurationCallback(displayCallback, Unmanaged.passUnretained(box).toOpaque())
        return CallbackObservation { [weak self] in
            CGDisplayRemoveReconfigurationCallback(displayCallback, Unmanaged.passUnretained(box).toOpaque())
            self?.box = nil
        }
    }
}

@MainActor
public final class LivePowerSourceInfo: PowerSourceInfo {
    private var box: CallbackBox?
    private var source: CFRunLoopSource?

    public init() {}

    public func isOnACPower() -> Bool {
        (IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String?) == kIOPMACPowerKey
    }

    public func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let box = CallbackBox(handler)
        self.box = box
        let source = IOPSNotificationCreateRunLoopSource(powerCallback, Unmanaged.passUnretained(box).toOpaque())?
            .takeRetainedValue()
        self.source = source
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
        return CallbackObservation { [weak self] in
            if let source = self?.source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
            self?.source = nil
            self?.box = nil
        }
    }
}

@MainActor
public final class LiveThermalMonitor: ThermalMonitoring {
    public init() {}

    public func currentLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    public func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let token = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return CallbackObservation { NotificationCenter.default.removeObserver(token) }
    }
}

/// A cancellable registration, so observers look like every other ScheduledTask.
@MainActor
final class CallbackObservation: ScheduledTask {
    private var onCancel: (@MainActor () -> Void)?

    init(_ onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}
