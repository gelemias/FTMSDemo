import Foundation

/// Builds FTMS Fitness Machine Control Point packets.
enum FTMSCommandEncoder {
    static func controlPoint(opcode: UInt8) -> Data { Data([opcode]) }

    static func targetSpeed(kmh: Double) -> Data {
        let value = UInt16(kmh * 100)
        return Data([0x02, UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }
}
