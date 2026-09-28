import Foundation

/// Decodes the FTMS Treadmill Data characteristic without Bluetooth or UI dependencies.
struct FTMSDataParser {
    func parse(_ data: Data) -> TreadmillData? {
        var cursor = 0

        func canRead(_ count: Int) -> Bool { cursor + count <= data.count }

        func readUInt8() -> UInt8? {
            guard canRead(1) else { return nil }
            defer { cursor += 1 }
            return data[cursor]
        }

        func readUInt16() -> UInt16? {
            guard canRead(2) else { return nil }
            defer { cursor += 2 }
            return UInt16(data[cursor]) | (UInt16(data[cursor + 1]) << 8)
        }

        func readUInt24() -> UInt32? {
            guard canRead(3) else { return nil }
            defer { cursor += 3 }
            return UInt32(data[cursor]) |
                (UInt32(data[cursor + 1]) << 8) |
                (UInt32(data[cursor + 2]) << 16)
        }

        @discardableResult
        func skip(_ count: Int) -> Bool {
            guard canRead(count) else { return false }
            cursor += count
            return true
        }

        guard let flags = readUInt16(), let rawSpeed = readUInt16() else { return nil }

        var result = TreadmillData()
        result.speedKmh = Double(rawSpeed) / 100.0

        if flags[1] { _ = skip(2) }
        if flags[2], let rawDistance = readUInt24() { result.distanceMeters = Double(rawDistance) }

        if flags[3] {
            if let rawIncline = readUInt16() {
                result.incline = Double(Int16(bitPattern: rawIncline)) / 10.0
            }
            _ = skip(2) // Ramp angle.
        }

        if flags[4] { _ = skip(4) } // Positive and negative elevation gain.
        if flags[5], let rawPace = readUInt16() { result.paceMinPerKm = Double(rawPace) / 10.0 }
        if flags[6] { _ = skip(2) }
        if flags[7] { _ = skip(5) } // Total, per hour, per minute energy.
        if flags[8], let heartRate = readUInt8() { result.heartRate = Int(heartRate) }
        if flags[9] { _ = skip(1) }
        if flags[10] { _ = skip(2) }
        if flags[11] { _ = skip(2) }
        if flags[12] { _ = skip(4) }

        if result.paceMinPerKm == nil, let speed = result.speedKmh, speed > 0 {
            result.paceMinPerKm = 60.0 / speed
        }

        if let pace = result.paceMinPerKm, pace > 0 {
            result.cadenceSpm = Int((1000.0 / pace).rounded())
        }

        return result
    }
}

private extension UInt16 {
    subscript(bit: Int) -> Bool { (self & (1 << bit)) != 0 }
}
