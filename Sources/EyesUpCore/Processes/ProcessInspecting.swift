import Darwin
import Foundation

public protocol ProcessInspecting: Sendable {
    func identity(of pid: Int32) -> ProcessIdentity?
    func name(of pid: Int32) -> String?
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
}
