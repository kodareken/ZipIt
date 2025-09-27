//
//  Data+CRC32.swift
//  ZipIt
//
//  CRC32 implementation in pure Swift
//  Based on ITU V.42 specification with optimizations for RAR format
//

import Foundation

// MARK: - CRC32 (IEEE) and CRC16-IBM utilities

/// CRC32 calculation optimized for RAR format
public extension Data {
    /// Calculate CRC32 hash for data (compatible with RAR format)
    var crc32: UInt32 {
        return self.withUnsafeBytes { bytes in
            return calculateCRC32(bytes.baseAddress!, length: count)
        }
    }
    
    /// Calculate CRC32 hash for byte array
    private func calculateCRC32(_ buffer: UnsafeRawPointer, length: Int) -> UInt32 {
        // IEEE 802.3 CRC-32 (polynomial 0xEDB88320), reflected input/output
        let table = Self.crc32Table
        var crc: UInt32 = 0xFFFFFFFF  // Initial CRC value
        
        let byteBuffer = buffer.bindMemory(to: UInt8.self, capacity: length)
        for i in 0..<length {
            let index = (crc ^ UInt32(byteBuffer[i])) & 0xFF
            crc = (crc >> 8) ^ table[Int(index)]
        }
        return crc ^ 0xFFFFFFFF  // Final XOR value
    }
    
    private static let crc32Table: [UInt32] = buildCRC32Table()
    
    /// Build CRC32 lookup table (reflected polynomial 0xEDB88320)
    private static func buildCRC32Table() -> [UInt32] {
        var table: [UInt32] = Array(repeating: 0, count: 256)
        let poly: UInt32 = 0xEDB88320
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ poly
                } else {
                    crc >>= 1
                }
            }
            table[i] = crc
        }
        return table
    }
}

public extension Array where Element == UInt8 {
    var crc32: UInt32 { Data(self).crc32 }
}

/// CRC16-IBM (aka CRC-16/ARC): poly 0xA001 (reversed 0x8005), init 0xFFFF, reflected input/output, xorOut 0x0000
public extension Data {
    var crc16IBM: UInt16 {
        var crc: UInt16 = 0x0000
        self.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self)
            for b in ptr {
                let data = UInt16(b)
                crc ^= data
                for _ in 0..<8 {
                    let lsb = crc & 1
                    crc >>= 1
                    if lsb != 0 { crc ^= 0xA001 }
                }
            }
        }
        return crc
    }
}

public extension Array where Element == UInt8 {
    var crc16IBM: UInt16 { Data(self).crc16IBM }
}

// MARK: - DOS time (for RAR headers)
public enum DOSTime {
    /// Convert Date to MS-DOS date/time (packed into 32-bit: date high 16 bits, time low 16 bits)
    public static func from(_ date: Date) -> UInt32 {
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        let year = UInt32(max(1980, (comps.year ?? 1980))) - 1980
        let month = UInt32(comps.month ?? 1)
        let day = UInt32(comps.day ?? 1)
        let hour = UInt32(comps.hour ?? 0)
        let minute = UInt32(comps.minute ?? 0)
        let second = UInt32(comps.second ?? 0) / 2  // DOS stores seconds/2
        let time = (hour << 11) | (minute << 5) | second
        let date = (year << 9) | (month << 5) | day
        return (date << 16) | time
    }
}
