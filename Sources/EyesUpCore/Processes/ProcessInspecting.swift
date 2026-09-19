import Darwin
import Foundation

/// What one process looks like right now.
public struct ProcessDetails: Equatable, Sendable {
    public var name: String
    /// Total CPU seconds this process has used since it started.
    public var cpuSeconds: Double
    public var memoryBytes: UInt64
    public var threads: Int
    public var uid: uid_t
    public var identity: ProcessIdentity

    public init(name: String, cpuSeconds: Double, memoryBytes: UInt64, threads: Int, uid: uid_t, identity: ProcessIdentity) {
        self.name = name
        self.cpuSeconds = cpuSeconds
        self.memoryBytes = memoryBytes
        self.threads = threads
        self.uid = uid
        self.identity = identity
    }
}

public protocol ProcessInspecting: Sendable {
    func identity(of pid: Int32) -> ProcessIdentity?
    func name(of pid: Int32) -> String?
    func ownerUID(of pid: Int32) -> uid_t?
    func details(of pid: Int32) -> ProcessDetails?
    func allProcessIDs() -> [Int32]
    func executablePath(of pid: Int32) -> String?
}

/// Reads process facts with libproc. It works without admin rights for the user's own processes.
public struct LibprocInspector: ProcessInspecting {
    public init() {}

    public func identity(of pid: Int32) -> ProcessIdentity? {
        guard let info = bsdInfo(pid) else { return nil }
        return ProcessIdentity(pid: pid, startTime: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    public func name(of pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
            return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self)).lastPathComponent
        }
        guard let info = bsdInfo(pid) else { return nil }
        let comm = withUnsafeBytes(of: info.pbi_comm) { raw in Array(raw.prefix { $0 != 0 }) }
        return comm.isEmpty ? nil : String(decoding: comm, as: UTF8.self)
    }

    private func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    public func ownerUID(of pid: Int32) -> uid_t? {
        bsdInfo(pid).map { $0.pbi_uid }
    }

    public func allProcessIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let written = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard written > 0 else { return [] }
        return pids.prefix(Int(written)).filter { $0 > 0 }
    }

    /// Resource usage for one process. Fails for processes this user can't inspect, which is expected.
    public func details(of pid: Int32) -> ProcessDetails? {
        guard let info = bsdInfo(pid), let identity = identity(of: pid) else { return nil }
        var usage = rusage_info_v4()
        let usageRead = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        var taskInfo = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let taskRead = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize) == taskSize

        let cpuSeconds = usageRead == 0
            ? Double(usage.ri_user_time + usage.ri_system_time) / 1_000_000_000
            : (taskRead ? Double(taskInfo.pti_total_user + taskInfo.pti_total_system) / 1_000_000_000 : 0)
        let memory = usageRead == 0 ? usage.ri_phys_footprint : (taskRead ? UInt64(taskInfo.pti_resident_size) : 0)

        return ProcessDetails(
            name: name(of: pid) ?? "process \(pid)",
            cpuSeconds: cpuSeconds,
            memoryBytes: memory,
            threads: taskRead ? Int(taskInfo.pti_threadnum) : 0,
            uid: info.pbi_uid,
            identity: identity
        )
    }

    public func executablePath(of pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
