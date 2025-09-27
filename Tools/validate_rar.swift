import Foundation

struct RAR4Validator {
    struct Cursor {
        var data: Data
        var offset: Int = 0
        mutating func read(_ n: Int) -> Data { defer { offset += n }; return data.subdata(in: offset..<(offset+n)) }
        mutating func readU8() -> UInt8 { read(1)[0] }
        mutating func readLE16() -> UInt16 { let d = read(2); return d.withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian }
        mutating func readLE32() -> UInt32 { let d = read(4); return d.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian }
    }

    static func crc16IBM(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0x0000
        for b in data { crc ^= UInt16(b); for _ in 0..<8 { let lsb = crc & 1; crc >>= 1; if lsb != 0 { crc ^= 0xA001 } } }
        return crc
    }

    static func crc32(_ data: Data) -> UInt32 { return (data as NSData).crc32() }
}

extension NSData {
    // Simple CRC32 via zlib if available; fallback to a small table
    @inline(__always) func crc32() -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        let poly: UInt32 = 0xEDB88320
        for i in 0..<256 { var c = UInt32(i); for _ in 0..<8 { c = (c & 1) != 0 ? (poly ^ (c >> 1)) : (c >> 1) }; table[i] = c }
        var crc: UInt32 = 0xFFFFFFFF
        let bytes = self.bytes.bindMemory(to: UInt8.self, capacity: self.length)
        for i in 0..<self.length { let idx = Int((crc ^ UInt32(bytes[i])) & 0xFF); crc = (crc >> 8) ^ table[idx] }
        return crc ^ 0xFFFFFFFF
    }
}

@main
struct Main {
    static func main() throws {
        let url = URL(fileURLWithPath: "/tmp/zipit_rar_mvp.rar")
        let file = try Data(contentsOf: url)
        var cur = RAR4Validator.Cursor(data: file)
        // Signature
        let sig = cur.read(7)
        guard Array(sig) == [0x52,0x61,0x72,0x21,0x1A,0x07,0x00] else { fatalError("Bad signature") }
        // Main header
        let mainCRC = cur.readLE16()
        let mainType = cur.readU8(); let mainFlags = cur.readLE16(); let mainSize = cur.readLE16()
        let mainHdrRange = (cur.offset-3)..<(cur.offset-3 + Int(mainSize - 2))
        let mainHdrData = file.subdata(in: mainHdrRange)
        // RAR4 header CRC uses init 0xFFFF
        let calcMainCRC = mainHdrData.reduce(UInt16(0xFFFF)) { (crc, byte) in
            var c = crc ^ UInt16(byte)
            var r = c
            for _ in 0..<8 { let lsb = r & 1; r >>= 1; if lsb != 0 { r ^= 0xA001 } }
            return r
        }
        guard mainType == 0x73 else { fatalError("Main header type mismatch: \(String(mainType, radix:16))") }
        if mainCRC != calcMainCRC {
            print("Main CRC mismatch: stored=\(String(mainCRC, radix:16)) calc=\(String(calcMainCRC, radix:16)) rangeLen=\(mainHdrData.count)")
            fatalError("Main header CRC mismatch")
        }
        // File header
        let fCRC = cur.readLE16(); let fType = cur.readU8(); let fFlags = cur.readLE16(); let fSize = cur.readLE16(); let addSize = cur.readLE32()
        // Body length (HEAD_SIZE excludes ADD_SIZE)
        let fBodyLen = Int(fSize) - 7
        let fBody = cur.read(fBodyLen)
        // CRC16 over header bytes [TYPE,FLAGS,SIZE, BODY] (exclude ADD_SIZE)
        var headerCore = Data()
        headerCore.append(contentsOf: [fType])
        withUnsafeBytes(of: fFlags.littleEndian) { headerCore.append(contentsOf: $0) }
        withUnsafeBytes(of: fSize.littleEndian) { headerCore.append(contentsOf: $0) }
        headerCore.append(fBody)
        let calcF = headerCore.reduce(UInt16(0xFFFF)) { (crc, byte) in
            var r = crc ^ UInt16(byte)
            for _ in 0..<8 { let lsb = r & 1; r >>= 1; if lsb != 0 { r ^= 0xA001 } }
            return r
        }
        guard fType == 0x74 && fCRC == calcF else { fatalError("File header CRC/type mismatch") }
        // Parse minimal fields from body
        var fbCur = RAR4Validator.Cursor(data: fBody)
        let packSize = fbCur.readLE32(); let unpSize = fbCur.readLE32(); _ = fbCur.readU8(); let fileCRC = fbCur.readLE32(); _ = fbCur.readLE32(); _ = fbCur.readU8(); let method = fbCur.readU8(); let nameLen = fbCur.readLE16(); _ = fbCur.readLE32(); let name = fbCur.read(Int(nameLen))
        // Payload
        let payload = cur.read(Int(addSize))
        // Check CRC32 over uncompressed data
        let calcFileCRC = Int(RAR4Validator.crc32(payload))
        print("OK signature\nMain: flags=\(mainFlags), size=\(mainSize)\nFile: method=0x\(String(method, radix:16)), name=\(String(data:name, encoding:.utf8) ?? "?"), pack=\(packSize), unp=\(unpSize)\nHeader CRCs OK. File CRC: stored=\(String(fileCRC, radix:16)), calc=\(String(calcFileCRC, radix:16)).")
    }
}
