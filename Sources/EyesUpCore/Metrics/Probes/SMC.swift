import Foundation
import IOKit

/// What SMCProbe needs from the SMC, so tests can supply readings without hardware.
public protocol SMCReading: AnyObject, Sendable {
    func read(_ key: String) -> Double?
}

/// Reads Apple's System Management Controller through its IOKit user client. No admin rights needed.
///
/// The request is an 80-byte C struct, built here as raw bytes because Swift's layout rules don't
/// match C's. The key field is a *native-endian* UInt32 while the payload stays big-endian; swapping
/// them makes every key come back "not found".
public final class SMC: SMCReading, @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()

    private static let structSize = 80
    private static let keyOffset = 0
    private static let dataSizeOffset = 28
    private static let dataTypeOffset = 32
    private static let data8Offset = 42
    private static let bytesOffset = 48
    private static let selectorReadKey: UInt8 = 5
    private static let selectorKeyInfo: UInt8 = 9

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public func read(_ key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0 else { return nil }

        var info = [UInt8](repeating: 0, count: Self.structSize)
        Self.writeNative(&info, Self.keyOffset, Self.fourCharCode(key))
        info[Self.data8Offset] = Self.selectorKeyInfo
        guard let infoOut = call(info) else { return nil }
        let size = Int(Self.readNative(infoOut, Self.dataSizeOffset))
        let typeCode = Self.readNative(infoOut, Self.dataTypeOffset)
        guard size > 0, size <= 32 else { return nil }

        var request = [UInt8](repeating: 0, count: Self.structSize)
        Self.writeNative(&request, Self.keyOffset, Self.fourCharCode(key))
        Self.writeNative(&request, Self.dataSizeOffset, UInt32(size))
        Self.writeNative(&request, Self.dataTypeOffset, typeCode)
        request[Self.data8Offset] = Self.selectorReadKey
        guard let out = call(request) else { return nil }

        let payload = Array(out[Self.bytesOffset..<(Self.bytesOffset + size)])
        return Self.decode(payload, type: Self.string(typeCode))
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outputSize = Self.structSize
        let result = input.withUnsafeBytes { inputPointer in
            output.withUnsafeMutableBytes { outputPointer in
                IOConnectCallStructMethod(connection, 2, inputPointer.baseAddress, Self.structSize,
                                          outputPointer.baseAddress, &outputSize)
            }
        }
        return result == kIOReturnSuccess ? output : nil
    }

    private static func decode(_ payload: [UInt8], type: String) -> Double? {
        switch type.trimmingCharacters(in: CharacterSet(charactersIn: " \0")) {
        case "flt" where payload.count == 4:
            let bits = UInt32(payload[0]) | UInt32(payload[1]) << 8 | UInt32(payload[2]) << 16 | UInt32(payload[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case "ui8" where payload.count >= 1:
            return Double(payload[0])
        case "ui16" where payload.count >= 2:
            return Double(UInt16(payload[0]) << 8 | UInt16(payload[1]))
        case "ui32" where payload.count >= 4:
            return Double((UInt32(payload[0]) << 24) | (UInt32(payload[1]) << 16) | (UInt32(payload[2]) << 8) | UInt32(payload[3]))
        case "sp78" where payload.count >= 2:
            return Double(Int16(bitPattern: UInt16(payload[0]) << 8 | UInt16(payload[1]))) / 256
        case "fpe2" where payload.count >= 2:
            return Double(UInt16(payload[0]) << 8 | UInt16(payload[1])) / 4
        default:
            return nil
        }
    }

    private static func fourCharCode(_ key: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in key.utf8.prefix(4) { value = (value << 8) | UInt32(byte) }
        return value
    }

    private static func string(_ code: UInt32) -> String {
        var result = ""
        for shift in stride(from: 24, through: 0, by: -8) {
            let byte = UInt8(truncatingIfNeeded: code >> UInt32(shift))
            if byte != 0 { result.append(Character(UnicodeScalar(byte))) }
        }
        return result
    }

    private static func writeNative(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        buffer[offset] = UInt8(truncatingIfNeeded: value)
        buffer[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        buffer[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        buffer[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    private static func readNative(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(buffer[offset]) | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16) | (UInt32(buffer[offset + 3]) << 24)
    }
}
